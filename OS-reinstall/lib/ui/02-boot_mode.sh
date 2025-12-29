#!/usr/bin/env bash

ui_boot_mode_select() {
  local detected="$1"
  local outvar="$2"
  local rc pick

  set +e
  pick="$(
    dialog --stdout --clear \
      --backtitle "OVH VPS Rescue Installer" \
      --cancel-label "Back" \
      --extra-button --extra-label "Cancel" \
      --radiolist "Detected: ${detected}\n\nChoose boot mode for installation:" 14 74 4 \
      "auto" "Use detected (${detected})" "on" \
      "uefi" "UEFI (ESP + grub-efi)" "off" \
      "bios" "Legacy (BIOS/CSM) (bios_grub + grub-pc)" "off" \
      </dev/tty 2>/dev/tty
  )"
  rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    printf -v "$outvar" '%s' "$pick"
    return 0
  fi

  # Back => return to previous screen, Cancel/ESC => abort installer
  [[ $rc -eq 3 || $rc -eq 255 ]] && ui_abort
  [[ $rc -eq 1 ]] && return 1
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
  local outaction="$3"

  local had_errexit=0
  case $- in *e*) had_errexit=1;; esac

  local choice rc
  set +e
  choice="$(
    dialog --clear --stdout \
      --title "Выбор режима загрузки" \
      --ok-label "Применить" \
      --cancel-label "Отмена" \
      --extra-button \
      --extra-label "Назад" \
      --menu "Выберите режим загрузки (detected: ${detected}):" 12 70 4 \
        uefi "UEFI" \
        bios "Legacy (BIOS)"
  )"
  rc=$?
  ((had_errexit)) && set -e

  dialog --clear
  clear

  case "$rc" in
    0)
      # Apply
      [[ -n "$choice" ]] || { printf -v "$outaction" '%s' "cancel"; return 0; }
      printf -v "$outvar" '%s' "$choice"
      printf -v "$outaction" '%s' "apply"
      return 0
      ;;
    3)
      # Back
      printf -v "$outaction" '%s' "back"
      return 0
      ;;
    1|255)
      # Cancel / ESC
      printf -v "$outaction" '%s' "cancel"
      return 0
      ;;
    *)
      # Реальная ошибка dialog
      printf -v "$outaction" '%s' "error"
      return "$rc"
      ;;
  esac
}


