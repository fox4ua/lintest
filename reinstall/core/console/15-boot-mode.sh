#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_boot_mode_console() {
  local out_var="$1"
  local ans

  while true; do
    echo "Boot mode:"
    echo "  1) Auto"
    echo "  2) UEFI"
    echo "  3) BIOS (Legacy)"
    printf "Choose [1-3, 0=Cancel]: "
    read -r ans

    case "$ans" in
      0) return 1 ;;
      1) printf -v "$out_var" '%s' "auto"; return 0 ;;
      2) printf -v "$out_var" '%s' "uefi"; return 0 ;;
      3) printf -v "$out_var" '%s' "bios"; return 0 ;;
      *) echo "Invalid choice. Try again." ;;
    esac
  done
}
