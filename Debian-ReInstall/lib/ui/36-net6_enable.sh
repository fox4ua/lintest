#!/usr/bin/env bash

# ui_pick_net6_enable OUT_ENABLE
# return: 0=Continue, 1=Cancel/ESC (exit), 2=Back
ui_pick_net6_enable() {
  local out="$1"
  local rc choice

  choice="$(
    ui_dialog dialog --clear --stdout \
      --title "IPv6" \
      --ok-label "Continue" \
      --cancel-label "Cancel" \
      --help-button --help-label "Back" \
      --menu "Enable IPv6?" 12 60 4 \
        1 "Yes (use IPv6)" \
        0 "No (IPv6 disabled)"
  )"
  rc=$?
  ui_clear

  case "$rc" in
    0) : ;;
    2) return 2 ;;
    *) return 1 ;;
  esac

  case "$choice" in
    0|1) : ;;
    *) ui_msg "Incorrect selection: $choice"; return 2 ;;
  esac

  printf -v "$out" "%s" "$choice"
  return 0
}
