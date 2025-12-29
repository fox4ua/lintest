#!/usr/bin/env bash

ui_pick_boot_mode() {
  local detected="$1"
  local pick rc

  pick=$(dialog --stdout --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Boot mode" \
    --radiolist "Detected: ${detected}\n\nChoose boot mode for installation:" 14 74 4 \
      "auto" "Use detected (${detected})" "on" \
      "uefi" "UEFI (ESP + grub-efi)" "off" \
      "bios" "Legacy (BIOS/CSM) (bios_grub + grub-pc)" "off" \
    2>/dev/tty
  )
  rc=$?

  # Cancel/ESC
  if [[ $rc -ne 0 ]]; then
    ui_abort
  fi

  case "$pick" in
    auto|"")
      echo "$detected"
      ;;

    uefi)
      if ! has_uefi_rescue; then
        dialog --clear \
          --backtitle "OVH VPS Rescue Installer" \
          --title "Warning: UEFI not detected in Rescue" \
          --yes-label "Continue" \
          --no-label "Back" \
          --yesno \
"You selected UEFI, but this Rescue environment does NOT expose UEFI (/sys/firmware/efi is missing).

On many VPS this means UEFI boot may NOT be available, and the installed system could become unbootable.

Continue forcing UEFI anyway?" 15 86
        rc=$?
        [[ $rc -eq 255 ]] && ui_abort
        if [[ $rc -ne 0 ]]; then
          # "Back" -> fallback to detected
          echo "$detected"
          return 0
        fi
      fi
      echo "uefi"
      ;;

    bios)
      if has_uefi_rescue; then
        dialog --clear \
          --backtitle "OVH VPS Rescue Installer" \
          --title "Warning: UEFI detected in Rescue" \
          --yes-label "Continue" \
          --no-label "Back" \
          --yesno \
"You selected Legacy (BIOS/CSM), but this Rescue environment exposes UEFI.

If the VPS is configured to boot only in UEFI mode, Legacy installation may not boot.

Continue forcing Legacy anyway?" 14 86
        rc=$?
        [[ $rc -eq 255 ]] && ui_abort
        if [[ $rc -ne 0 ]]; then
          echo "$detected"
          return 0
        fi
      fi
      echo "bios"
      ;;

    *)
      die "Invalid boot mode selection: $pick"
      ;;
  esac
}
