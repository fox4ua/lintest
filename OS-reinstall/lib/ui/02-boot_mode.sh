#!/usr/bin/env bash

ui_boot_mode_select() {
  local detected="$1"
  local outvar="$2"
  local rc

  set +e
  ui_radiolist_safe "$outvar" 14 74 4 \
    "Detected: ${detected}\n\nChoose boot mode for installation:" \
      "auto" "Use detected (${detected})" "on" \
      "uefi" "UEFI (ESP + grub-efi)" "off" \
      "bios" "Legacy (BIOS/CSM) (bios_grub + grub-pc)" "off"
  rc=$?
  set -e

  # Cancel/ESC => abort installer
  [[ $rc -eq 1 || $rc -eq 255 ]] && ui_abort
  return 0
}

ui_warn_force_uefi_when_no_uefi_rescue() {
  ui_yesno_safe \
    "Warning: UEFI not detected in Rescue" \
"You selected UEFI, but this Rescue environment does NOT expose UEFI (/sys/firmware/efi is missing).

On many VPS this means UEFI boot may NOT be available, and the installed system could become unbootable.

Continue forcing UEFI anyway?" \
    15 86
}

ui_warn_force_bios_when_uefi_rescue() {
  ui_yesno_safe \
    "Warning: UEFI detected in Rescue" \
"You selected Legacy (BIOS/CSM), but this Rescue environment exposes UEFI.

If the VPS is configured to boot only in UEFI mode, Legacy installation may not boot.

Continue forcing Legacy anyway?" \
    14 86
}

# Main entry: detected + OUTVAR (NO subshell!)
ui_pick_boot_mode() {
  local detected="$1"
  local outvar="$2"
  local pick rc

  while true; do
    ui_boot_mode_select "$detected" pick

    case "$pick" in
      auto|"")
        printf -v "$outvar" '%s' "$detected"
        return 0
        ;;

      uefi)
        if ! has_uefi_rescue; then
          set +e
          ui_warn_force_uefi_when_no_uefi_rescue
          rc=$?
          set -e

          [[ $rc -eq 255 ]] && ui_abort
          [[ $rc -eq 1 ]] && continue   # Back

          # rc=0 -> Continue
        fi

        printf -v "$outvar" '%s' "uefi"
        return 0
        ;;

      bios)
        if has_uefi_rescue; then
          set +e
          ui_warn_force_bios_when_uefi_rescue
          rc=$?
          set -e

          [[ $rc -eq 255 ]] && ui_abort
          [[ $rc -eq 1 ]] && continue
        fi

        printf -v "$outvar" '%s' "bios"
        return 0
        ;;

    esac
  done
}
