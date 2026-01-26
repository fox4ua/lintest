#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_boot_size_console() {
  local out_var="$1"
  local ans

  while true; do
    echo "/boot size:"
    echo "  1) 256 MiB"
    echo "  2) 512 MiB"
    echo "  3) 1024 MiB"
    printf "Choose [1-3, 0=Cancel]: "
    read -r ans

    case "$ans" in
      0) return 1 ;;
      1) printf -v "$out_var" '%s' "256";  return 0 ;;
      2) printf -v "$out_var" '%s' "512";  return 0 ;;
      3) printf -v "$out_var" '%s' "1024"; return 0 ;;
      *) echo "Invalid choice. Try again." ;;
    esac
  done
}
