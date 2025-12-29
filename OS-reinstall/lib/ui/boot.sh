#!/usr/bin/env bash

ui_pick_boot() {
  local out
  out=$(dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "/boot size" \
    --radiolist "Select /boot size:" 13 70 5 \
      "min" "Minimal 512 MB" "on" \
      "mid" "Medium 1 GB" "off" \
      "max" "Maximum 2 GB" "off" \
    3>&1 1>&2 2>&3) || ui_abort
  echo "$out"
}
