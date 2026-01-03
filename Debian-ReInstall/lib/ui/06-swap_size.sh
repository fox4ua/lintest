#!/usr/bin/env bash

# ui_pick_swap_size OUT_SWAP_GIB
# return: 0=ok, 1=cancel/esc, 2=back
ui_pick_swap_size() {
  local out_swap="$1"
  local rc=0
  local choice=""

  choice="$(
    ui_dialog dialog --clear --stdout \
      --title "swap" \
      --ok-label "Далее" \
      --cancel-label "Отмена" \
      --help-button --help-label "Назад" \
      --menu "Выберите размер swap:" 15 74 7 \
        0  "Без swap" \
        1  "1 GiB" \
        2  "2 GiB" \
        4  "4 GiB" \
        8  "8 GiB" \
        16 "16 GiB"
  )"
  rc=$?
  ui_clear

  case "$rc" in
    0) : ;;
    2) return 2 ;;
    1|255) return 1 ;;
    *) return 1 ;;
  esac

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 0 || choice > 512 )); then
    ui_msg "Некорректный размер swap: $choice"
    return 2
  fi

  printf -v "$out_swap" "%s" "$choice"
  return 0
}
