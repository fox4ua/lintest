#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_boot_size_console() {
  local __out_var="$1"
  local ans

  while true; do
    echo "/boot size:"
    echo "  1) 256M"
    echo "  2) 512M"
    echo "  3) 1G"
    printf "Choose [1-3, 0=Cancel]: "
    read -r ans

    case "$ans" in
      0) return 1 ;;
      1) printf -v "$__out_var" '%s' "256M"; return 0 ;;
      2) printf -v "$__out_var" '%s' "512M"; return 0 ;;
      3) printf -v "$__out_var" '%s' "1G";   return 0 ;;
      *) echo "Invalid choice. Try again." ;;
    esac
  done
}
