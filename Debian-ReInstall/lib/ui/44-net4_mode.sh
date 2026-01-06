#!/usr/bin/env bash

# ui_pick_net4_mode OUT_NET_MODE
# return: 0=Continue, 1=Cancel/ESC (exit), 2=Back
ui_pick_net4_mode() {
  local out_mode="$1"
  local rc choice

  choice="$(
    ui_dialog dialog --clear --stdout \
      --title "Network" \
      --ok-label "Continue" \
      --cancel-label "Cancel" \
      --help-button --help-label "Back" \
      --menu "Select the network configuration mode:" 13 74 5 \
        dhcp   "DHCP (get the address automatically)" \
        static "Static (enter the IP address manually)"
  )"
  rc=$?
  ui_clear

  case "$rc" in
    0) : ;;
    2) return 2 ;;
    1|255) return 1 ;;
    *) return 1 ;;
  esac

  case "$choice" in
    dhcp|static) : ;;
    *) ui_msg "Incorrect network mode selection: $choice"; return 2 ;;
  esac

  printf -v "$out_mode" "%s" "$choice"
  return 0
}
