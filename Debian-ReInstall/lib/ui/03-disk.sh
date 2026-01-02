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

    --yesno "Этот диск используется текущей средой.\n\nТекущий / смонтирован из:\n${src_root:-unknown}\n\nВыбранный диск: $disk\n\nВыбери другой диск." 14 74
  local rc=$?
  ui_clear

  case "$rc" in
    0|2) return 2 ;;
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
    0) return 0 ;;
    2) return 2 ;;
    *) return 1 ;;
  esac
}


# ui_pick_disk OUT_DISK
# return: 0=ok (disk set), 1=cancel/esc, 2=back
ui_pick_disk() {
  local out_disk="$1"

  local choice rc warn_rc
  local -a items=()

  # собираем /dev/sdX, /dev/nvme0n1 и т.п.
  while IFS= read -r line; do
    local name type size model
    name="$(awk '{print $1}' <<<"$line")"
    type="$(awk '{print $2}' <<<"$line")"
    size="$(awk '{print $3}' <<<"$line")"
    model="$(cut -d' ' -f4- <<<"$line")"

    [[ "$type" == "disk" ]] || continue

    local dev="/dev/$name"
    [[ -b "$dev" ]] || continue

    [[ -n "$model" ]] || model="-"
    items+=("$dev" "${size}  ${model}")
  done < <(lsblk -dn -o NAME,TYPE,SIZE,MODEL 2>/dev/null | sed 's/[[:space:]]\+/ /g')

  if [[ ${#items[@]} -eq 0 ]]; then
    ui_msg "Не найдено доступных дисков (lsblk вернул пусто)."
    return 1
  fi

  while true; do
    choice="$(
      ui_dialog dialog --clear --stdout \
        --title "Выбор диска" \
        --ok-label "Выбрать" \
        --cancel-label "Отмена" \
        --help-button \
        --help-label "Назад" \
        --menu "Выберите диск для установки (ВСЕ ДАННЫЕ БУДУТ УДАЛЕНЫ):" 18 74 10 \
        "${items[@]}"
    )"
    rc=$?
    ui_clear

    case "$rc" in
      0) : ;;
      2) return 2 ;;         # Back
      1|255) return 1 ;;     # Cancel/ESC
      *) return 1 ;;
    esac

    [[ -b "$choice" ]] || continue

    # Блокирующая проверка "системного диска" (как реализовано в текущем архиве)
# Блокирующая проверка: выбран диск текущей среды (rescue/live)
if disk_is_current_env_disk "$choice"; then
  ui_block_current_env_disk "$choice"
  case $? in
    2) continue ;;  # назад -> снова список дисков
    *) return 1 ;;  # отмена/esc
  esac
fi


    # Проверка занятости диска (mount/swap/lvm/md) и предложение "освободить"
# Только детект и запись флагов (действия будут потом, на стадии установки)
DISK_RELEASE_APPROVED=0
disk_detect_usage_flags "$choice"

if (( DISK_NEEDS_RELEASE )); then
  ui_warn_disk_busy_plan_only "$choice"
  case $? in
    0) DISK_RELEASE_APPROVED=1 ;;  # пользователь согласен “отключить позже”
    2) continue ;;                 # назад -> снова список дисков
    *) return 1 ;;                 # отмена/esc
  esac
fi


    printf -v "$out_disk" "%s" "$choice"
    return 0
  done
}


