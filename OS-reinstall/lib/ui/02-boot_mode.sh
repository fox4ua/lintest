#!/usr/bin/env bash
set -Eeuo pipefail

ui_boot_mode_menu() {
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

ui_boot_mode_warn_or_back() {
  local pick="$1"
  local detected="$2"
  local rc

  if [[ "$pick" == "uefi" && ! -d /sys/firmware/efi ]]; then
    dialog --clear \
      --backtitle "OVH VPS Rescue Installer" \
      --title "Warning: UEFI not detected in Rescue" \
      --yes-label "Continue" \
      --no-label "Back" \
      --yesno \
"You selected UEFI, but this Rescue environment does NOT expose UEFI (/sys/firmware/efi is missing).

On many VPS this means UEFI boot may NOT be available, and the installed system could become unbootable.

Continue forcing UEFI anyway?" 15 86 </dev/tty 2>/dev/tty
    rc=$?
    [[ $rc -eq 255 ]] && ui_abort
    [[ $rc -ne 0 ]] && echo "back" && return 0
  fi

  if [[ "$pick" == "bios" && -d /sys/firmware/efi ]]; then
    dialog --clear \
      --backtitle "OVH VPS Rescue Installer" \
      --title "Warning: UEFI detected in Rescue" \
      --yes-label "Continue" \
      --no-label "Back" \
      --yesno \
"You selected Legacy (BIOS/CSM), but this Rescue environment exposes UEFI.

If the VPS is configured to boot only in UEFI mode, Legacy installation may not boot.

Continue forcing Legacy anyway?" 14 86 </dev/tty 2>/dev/tty
    rc=$?
    [[ $rc -eq 255 ]] && ui_abort
    [[ $rc -ne 0 ]] && echo "back" && return 0
  fi

  echo "ok"
}

ui_pick_boot_mode() {
  local detected="$1"
  local out_var="$2"

  local pick rc action

  while true; do
    pick="$(ui_boot_mode_menu "$detected")"
    rc=$?
    [[ $rc -ne 0 ]] && ui_abort      # Cancel/ESC в меню -> abort ВСЕГО скрипта

    if [[ "$pick" == "auto" || -z "$pick" ]]; then
      printf -v "$out_var" '%s' "$detected"
      return 0
    fi

    action="$(ui_boot_mode_warn_or_back "$pick")"
    rc=$?
    [[ $rc -ne 0 ]] && ui_abort      # ESC в warning -> abort ВСЕГО скрипта

    [[ "$action" == "back" ]] && continue

    printf -v "$out_var" '%s' "$pick"
    return 0
  done
}


