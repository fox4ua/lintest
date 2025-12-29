#!/usr/bin/env bash

ui_pick_boot_mode() {
  local detected="$1"
  local pick rc

  pick="$(dialog --stdout --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Boot mode" \
    --radiolist "Detected: ${detected}\n\nChoose boot mode for installation:" 14 74 4 \
      "auto" "Use detected (${detected})" "on" \
      "uefi" "UEFI (ESP + grub-efi)" "off" \
      "bios" "Legacy (BIOS/CSM) (bios_grub + grub-pc)" "off" \
    2>/dev/tty
  )"
  rc=$?

  # Cancel/ESC
  if [[ $rc -ne 0 ]]; then
    ui_abort
  fi


}
