#!/usr/bin/env bash

ui_pick_net_mode() {
  local out
  out=$(dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Network mode" \
    --radiolist "Network config:" 12 72 4 \
      "dhcp" "DHCP" "on" \
      "static" "Static IPv4" "off" \
    3>&1 1>&2 2>&3) || ui_abort
  echo "$out"
}
