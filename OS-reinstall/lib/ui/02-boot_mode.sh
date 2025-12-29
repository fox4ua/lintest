#!/usr/bin/env bash
# Split boot-mode UI into 3 functions:
# 1) boot-mode chooser window
# 2) warning for forcing UEFI when Rescue is not UEFI
# 3) warning for forcing BIOS when Rescue is UEFI

ui_boot_mode_select() {
  local detected="$1"
  local pick

  pick="$(
    dialog --stdout --clear \
      --backtitle "OVH VPS Rescue Installer" \
      --title "Boot mode" \
      --radiolist "Detected: ${detected}\n\nChoose boot mode for installation:" 14 74 4 \
        "auto" "Use detected (${detected})" "on" \
        "uefi" "UEFI (ESP + grub-efi)" "off" \
        "bios" "Legacy (BIOS/CSM) (bios_grub + grub-pc)" "off" \
      </dev/tty 2>/dev/tty
  )" || ui_abort

  echo "$pick"
}

ui_warn_force_uefi_when_no_uefi_rescue() {
  # Return codes:
  # 0 -> continue forcing UEFI
  # 1 -> back (do not force, let caller decide)
  # 255 -> cancel/esc (abort)
  dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Warning: UEFI not detected in Rescue" \
    --yes-label "Continue" \
    --no-label "Back" \
    --yesno \
"You selected UEFI, but this Rescue environment does NOT expose UEFI (/sys/firmware/efi is missing).

On many VPS this means UEFI boot may NOT be available, and the installed system could become unbootable.

Continue forcing UEFI anyway?" 15 86 </dev/tty 2>/dev/tty
}

ui_warn_force_bios_when_uefi_rescue() {
  # Return codes:
  # 0 -> continue forcing BIOS
  # 1 -> back (do not force, let caller decide)
  # 255 -> cancel/esc (abort)
  dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Warning: UEFI detected in Rescue" \
    --yes-label "Continue" \
    --no-label "Back" \
    --yesno \
"You selected Legacy (BIOS/CSM), but this Rescue environment exposes UEFI.

If the VPS is configured to boot only in UEFI mode, Legacy installation may not boot.

Continue forcing Legacy anyway?" 14 86 </dev/tty 2>/dev/tty
}

# Orchestrator (keeps your previous behavior: Back -> fallback to detected)
ui_pick_boot_mode() {
  local detected="$1"
  local pick rc

  pick="$(ui_boot_mode_select "$detected")"

  case "$pick" in
    auto|"")
      echo "$detected"
      ;;

    uefi)
      if ! has_uefi_rescue; then
        ui_warn_force_uefi_when_no_uefi_rescue
        rc=$?
        [[ $rc -eq 255 ]] && ui_abort
        if [[ $rc -ne 0 ]]; then
          echo "$detected"
          return 0
        fi
      fi
      echo "uefi"
      ;;

    bios)
      if has_uefi_rescue; then
        ui_warn_force_bios_when_uefi_rescue
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
