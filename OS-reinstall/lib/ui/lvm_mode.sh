#!/usr/bin/env bash

ui_pick_lvm_mode() {
  local out
  out=$(dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "LVM mode" \
    --radiolist "Select LVM mode:" 12 74 4 \
      "linear" "Classic LVM (linear)" "on" \
      "thin"   "LVM-thin (thin pool)" "off" \
    3>&1 1>&2 2>&3) || ui_abort
  echo "$out"
}
