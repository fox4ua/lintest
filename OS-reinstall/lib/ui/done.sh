#!/usr/bin/env bash

ui_done_and_reboot() {
  local boot_mode="$1" lvm_mode="$2" net_mode="$3" iface="$4" backend="$5"

  dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Done" --msgbox "Completed.

Boot: ${boot_mode}
LVM:  ${lvm_mode}
Net:  ${net_mode} (${iface})
Cfg:  ${backend}

1) Reboot
2) Disable Rescue mode in OVH panel (boot from disk)
3) SSH as root with chosen password

Log: ${LOG_FILE}" 20 90 || ui_abort

  clear
  reboot
}
