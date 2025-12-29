#!/usr/bin/env bash

ui_pick_mirror() {
  local out
  out=$(dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Debian mirror" \
    --radiolist "Select mirror:" 12 86 3 \
      "http://deb.debian.org/debian" "deb.debian.org (recommended)" "on" \
      "http://ftp.de.debian.org/debian" "ftp.de.debian.org" "off" \
      "http://ftp.fr.debian.org/debian" "ftp.fr.debian.org" "off" \
    3>&1 1>&2 2>&3) || ui_abort
  echo "$out"
}
