#!/usr/bin/env bash

# warning: disk is current system disk
# return: 2=Back, 1=Cancel/ESC
ui_block_current_env_disk() {
  local disk="$1"
  local src_root
  src_root="$(findmnt -no SOURCE / 2>/dev/null || true)"

  ui_dialog dialog --clear \
    --title "Нельзя выбрать этот диск" \
    --yes-label "Назад" \
    --no-label "Отмена" \
    --help-button \
    --help-label "Назад" \
    --yesno "Этот диск используется текущей средой.\n\nТекущий / смонтирован из:\n${src_root:-unknown}\n\nВыбранный диск: $disk\n\nВыбери другой диск." 14 74
  local rc=$?
  ui_clear

  case "$rc" in
    0|2) return 2 ;;     # Назад
    1|255) return 1 ;;   # Отмена/ESC
    *) return 1 ;;
  esac
}


# warning: disk busy -> release?
# return: 0=Release&Continue, 2=Back, 1=Cancel/ESC
ui_warn_disk_busy_plan_only() {
  local disk="$1"
  local text="На выбранном диске обнаружены активные ресурсы.\n\nДиск: $disk\n\n"

  (( DISK_HAS_MOUNTS )) && text+="• Есть примонтированные разделы\n"
  (( DISK_HAS_SWAP   )) && text+="• Есть активный swap\n"
  (( DISK_HAS_LVM    )) && text+="• Есть LVM PV\n"
  (( DISK_HAS_MD     )) && text+="• Возможно mdraid\n"

  text+="\nПеред разметкой их нужно будет отключить.\nОтключить (позже) и продолжить?"

  ui_dialog dialog --clear \
    --title "Диск используется" \
    --yes-label "Отключить" \
    --no-label "Отмена" \
    --help-button \
    --help-label "Назад" \
    --yesno "$text" 16 74
  local rc=$?
  ui_clear

  case "$rc" in
    0) return 0 ;;       # “Отключить” (только планируем)
    2) return 2 ;;       # Назад
    1|255) return 1 ;;   # Отмена/ESC
    *) return 1 ;;
  esac
}


# ui_pick_disk OUT_DISK
# return: 0=ok (disk set), 1=cancel/esc, 2=back
ui_pick_disk() {
  local out_disk="$1"
  local choice rc

  while true; do
    # ...твой список дисков через lsblk и dialog --menu...
    choice="$(
      ui_dialog dialog --clear --stdout \
        --title "Выбор диска" \
        --ok-label "Выбрать" \
        --cancel-label "Отмена" \
        --help-button \
        --help-label "Назад" \
        --menu "Выберите диск для установки:" 18 74 10 \
        "${DISK_MENU_ITEMS[@]}"
    )"
    rc=$?
    ui_clear

    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac

    [[ -b "$choice" ]] || continue

    # 1) Блокирующая проверка: диск текущей среды -> только назад/отмена
    if disk_is_current_env_disk "$choice"; then
      ui_block_current_env_disk "$choice"
      case $? in
        2) continue ;;   # назад -> снова список дисков
        *) return 1 ;;   # отмена/esc -> выход
      esac
    fi

    # 2) Не блокируем: просто детект и запись флагов/решения
    DISK_RELEASE_APPROVED=0
    disk_detect_usage_flags "$choice"

    if (( DISK_NEEDS_RELEASE )); then
      ui_warn_disk_busy_plan_only "$choice"
      case $? in
        0) DISK_RELEASE_APPROVED=1 ;;  # только запланировали “release позже”
        2) continue ;;                 # назад -> снова список дисков
        *) return 1 ;;                 # отмена/esc
      esac
    fi

    # 3) Фиксируем выбор
    printf -v "$out_disk" "%s" "$choice"
    return 0
  done
}

