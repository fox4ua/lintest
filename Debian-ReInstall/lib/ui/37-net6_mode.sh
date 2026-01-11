#!/usr/bin/env bash

# ui_pick_net6_mode OUT_MODE
# return: 0=Continue, 1=Cancel/ESC (exit), 2=Back
ui_pick_net6_mode() {
  local out="$1"
  local rc choice

  choice="$(
    ui_dialog dialog --clear --stdout \
      --title "IPv6 mode" \
      --ok-label "Continue" \
      --cancel-label "Cancel" \
      --help-button --help-label "Back" \
      --menu "IPv6 mode:" 12 60 4 \
        dhcp   "DHCPv6 / SLAAC" \
        static "Static IPv6"
  )"
  rc=$?
  ui_clear

  case "$rc" in
    0) printf -v "$out" "%s" "$choice"; return 0 ;;
    2) return 2 ;;
    *) return 1 ;;
  esac
}
