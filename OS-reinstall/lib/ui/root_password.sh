#!/usr/bin/env bash

ui_input_root_password() {
  local p1 p2
  while true; do
    p1=$(dialog --clear \
      --backtitle "OVH VPS Rescue Installer" \
      --title "Root password" \
      --insecure --passwordbox "Enter root password:" 10 60 \
      3>&1 1>&2 2>&3) || ui_abort

    p2=$(dialog --clear \
      --backtitle "OVH VPS Rescue Installer" \
      --title "Root password" \
      --insecure --passwordbox "Confirm:" 10 60 \
      3>&1 1>&2 2>&3) || ui_abort

    [[ -n "$p1" && "$p1" == "$p2" && ${#p1} -ge 8 ]] && { echo "$p1"; return 0; }

    dialog --backtitle "OVH VPS Rescue Installer" --title "Root password" --msgbox "Password mismatch / too short (min 8)." 7 48 || ui_abort
  done
}
