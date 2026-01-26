#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_swap_console() {
  local out_var="$1"
  local ans

  while true; do
    echo "Swap:"
    echo "  1) none"
    echo "  2) 1 GiB"
    echo "  3) 2 GiB"
    echo "  4) 4 GiB"
    printf "Choose [1-4, 0=Cancel]: "
    read -r ans

    case "$ans" in
      0) return 1 ;;
      1) printf -v "$out_var" '%s' "0";    return 0 ;;
      2) printf -v "$out_var" '%s' "1024"; return 0 ;;
      3) printf -v "$out_var" '%s' "2048"; return 0 ;;
      4) printf -v "$out_var" '%s' "4096"; return 0 ;;
      *) echo "Invalid choice. Try again." ;;
    esac
  done
}
