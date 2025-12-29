#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_boot_mode() {
  local detected="$1"
  local outvar="$2"
  local pick rc

  ui_dialog_to_var pick \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Boot mode" \
    --radiolist "Detected: ${detected}\n\nChoose boot mode for installation:" 14 74 4 \
      auto "Use detected (${detected})" on \
      uefi "UEFI (ESP + grub-efi)" off \
      bios "Legacy (BIOS/CSM) (bios_grub + grub-pc)" off

  case "$pick" in
    auto|"")
      printf -v "$outvar" '%s' "$detected"
      return 0
      ;;
    uefi|bios)
      # warnings (тоже через dialog_to_var не нужно, там yesno)
      if [[ "$pick" == "uefi" && ! -d /sys/firmware/efi ]]; then
        dialog --clear \
          --backtitle "OVH VPS Rescue Installer" \
          --title "Warning" \
          --yes-label "Continue" --no-label "Back" \
          --yesno "UEFI not detected in Rescue. Continue forcing UEFI?" 10 70 </dev/tty 2>/dev/tty
        rc=$?
        [[ $rc -eq 255 ]] && ui_abort
        [[ $rc -ne 0 ]] && { printf -v "$outvar" '%s' "$detected"; return 0; }
      fi

      if [[ "$pick" == "bios" && -d /sys/firmware/efi ]]; then
        dialog --clear \
          --backtitle "OVH VPS Rescue Installer" \
          --title "Warning" \
          --yes-label "Continue" --no-label "Back" \
          --yesno "UEFI detected in Rescue. Continue forcing Legacy?" 10 70 </dev/tty 2>/dev/tty
        rc=$?
        [[ $rc -eq 255 ]] && ui_abort
        [[ $rc -ne 0 ]] && { printf -v "$outvar" '%s' "$detected"; return 0; }
      fi

      printf -v "$outvar" '%s' "$pick"
      return 0
      ;;
    *)
      die "Invalid boot mode selection: $pick"
      ;;
  esac
}



