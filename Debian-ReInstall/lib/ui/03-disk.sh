#!/usr/bin/env bash

# warning: disk is current system disk
# return: 2=Back, 1=Cancel/ESC
disk_warn_blocking() {
  local text="$1"
  local rc
  ui_dialog dialog --clear     --title "Нельзя выбрать этот диск"     --yes-label "Назад"     --no-label "Отмена"     --yesno "$text" 14 74
  rc=$?
  ui_clear
  case "$rc" in
    0) return 2 ;;      # Назад
    1|255) return 1 ;;  # Отмена/ESC
    *) return 1 ;;
  esac
}

# warning: disk busy -> release?
# return: 0=Release&Continue, 2=Back, 1=Cancel/ESC
disk_warn_busy_release() {
  local text="$1"
  local rc
  ui_dialog dialog --clear     --title "Диск используется"     --yes-label "Отключить"     --no-label "Отмена"     --help-button     --help-label "Назад"     --yesno "$text" 18 74
  rc=$?
  ui_clear
  case "$rc" in
    0) return 0 ;;        # Отключить
    2) return 2 ;;        # Назад
    1|255) return 1 ;;    # Отмена/ESC
    *) return 1 ;;
  esac
}

# ui_pick_disk OUT_DISK
# return: 0=Apply, 1=Cancel/ESC, 2=Back
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
      ui_dialog dialog --clear --stdout         --title "Выбор диска"         --ok-label "Выбрать"         --cancel-label "Отмена"         --help-button         --help-label "Назад"         --menu "Выберите диск для установки (ВСЕ ДАННЫЕ БУДУТ УДАЛЕНЫ):" 18 74 10         "${items[@]}"
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

    # 1) Запрет: выбран диск, с которого сейчас работает система (не для переустановки из rescue)
    if ! disk_is_current_system_disk "$choice"; then
      disk_warn_blocking "${DISK_CHECK_REASON}

${DISK_CHECK_DETAILS}"
      warn_rc=$?
      case "$warn_rc" in
        2) continue ;;   # назад -> снова список дисков
        *) return 1 ;;   # отмена
      esac
    fi

    # 2) Если диск "занят" (mount/swap/lvm/md) — предложить отключить
    if disk_collect_busy_info "$choice"; then
      disk_warn_busy_release "${DISK_BUSY_SUMMARY}

Выбранный диск: $choice

${DISK_BUSY_DETAILS}
Отключить и продолжить?"
      warn_rc=$?
      case "$warn_rc" in
        0)
          if ! disk_release_locks "$choice"; then
            ui_msg "Не удалось освободить диск (umount/swapoff).

Закрой процессы, использующие диск, и повтори."
            continue
          fi
          ;;
        2) continue ;;      # назад
        *) return 1 ;;      # отмена
      esac
    fi

    printf -v "$out_disk" "%s" "$choice"
    return 0
  done
}
