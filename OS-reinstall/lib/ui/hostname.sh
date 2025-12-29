#!/usr/bin/env bash

ui_input_hostname() {
  local out
  out=$(dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Hostname" \
    --inputbox "Hostname (default pve):" 10 60 "pve" \
    3>&1 1>&2 2>&3) || ui_abort
  echo "$out"
}
