#!/usr/bin/env bash

ui_pick_static_profile() {
  local out
  out=$(dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Static profile" \
    --radiolist "Static mode profile:" 14 92 6 \
      "ovh32" "OVH /32 + gateway onlink (common OVH VPS)" "on" \
      "generic" "Generic static (CIDR + gateway)" "off" \
    3>&1 1>&2 2>&3) || ui_abort
  echo "$out"
}
