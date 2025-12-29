#!/usr/bin/env bash

ui_pick_swap() {
  local out
  out=$(dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Swap size" \
    --radiolist "Select swap size:" 12 60 4 \
      "1" "1 GB" "on" \
      "2" "2 GB" "off" \
      "4" "4 GB" "off" \
    3>&1 1>&2 2>&3) || ui_abort
  echo "$out"
}
