#!/usr/bin/env bash

ui_input_root_size() {
  local v
  v=$(dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Root size" \
    --inputbox "Root size in GB (default 30):" 10 60 "30" \
    3>&1 1>&2 2>&3) || ui_abort

  [[ "$v" =~ ^[0-9]+$ ]] || die "Root size must be integer"
  echo "$v"
}
