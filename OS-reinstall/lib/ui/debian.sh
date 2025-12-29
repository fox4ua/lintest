#!/usr/bin/env bash

ui_pick_debian() {
  local out
  out=$(dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Debian version" \
    --radiolist "Select Debian release:" 14 78 5 \
      "trixie"   "Debian 13 (trixie)" "on" \
      "bookworm" "Debian 12 (bookworm)" "off" \
      "bullseye" "Debian 11 (bullseye)" "off" \
    3>&1 1>&2 2>&3) || ui_abort
  echo "$out"
}
