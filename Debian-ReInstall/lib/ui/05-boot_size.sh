#!/usr/bin/env bash

# ui_pick_boot_size OUT_BOOT_MIB
# return: 0=ok, 1=cancel/esc, 2=back
ui_pick_boot_size() {
  local out_boot="$1"
  local rc=0
  local choice=""

  choice="$(
    ui_dialog dialog --clear --stdout \
      --title "/boot" \
      --ok-label "Далее" \
      --cancel-label "Отмена" \
      --help-button --help-label "Назад" \
      --menu "Выберите размер /boot:" 14 74 6 \
        256  "256 MiB (минимально)" \
        512  "512 MiB (рекомендуется)" \
        1024 "1024 MiB" \
        2048 "2048 MiB"
  )"
  rc=$?
  ui_clear

  case "$rc" in
    0) : ;;
    2) return 2 ;;
    1|255) return 1 ;;
    *) return 1 ;;
  esac

  # валидация
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 128 || choice > 8192 )); then
    ui_msg "Некорректный размер /boot: $choice"
    return 2
  fi

  printf -v "$out_boot" "%s" "$choice"
  return 0
}
