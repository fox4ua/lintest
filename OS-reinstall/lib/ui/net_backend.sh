#!/usr/bin/env bash

ui_pick_net_backend() {
  local out
  out=$(dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Network backend" \
    --radiolist "Choose how to configure network in target:" 13 86 4 \
      "ifupdown" "ifupdown (/etc/network/interfaces)" "on" \
      "networkd" "systemd-networkd (recommended for new Debian)" "off" \
    3>&1 1>&2 2>&3) || ui_abort
  echo "$out"
}
