#!/usr/bin/env bash

ui_pick_disk() {
  local items=()
  while read -r name size type; do
    [[ "$type" != "disk" ]] && continue
    items+=("/dev/$name" "/dev/$name ($size)" "off")
  done < <(lsblk -dn -o NAME,SIZE,TYPE)

  (( ${#items[@]} > 0 )) || die "No disks found."
  items[2]="on"

  local out
  out="$(
    dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Select target disk (WILL BE WIPED)" \
    --radiolist "Choose disk:" 15 78 6 "${items[@]}" \
    </dev/tty 2>/dev/tty
    )" || ui_abort

  echo "$out"
}
