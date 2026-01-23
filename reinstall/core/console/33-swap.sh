#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_swap_console() {
  local __out_var="$1"
  local ans

  while true; do
    echo "Swap:"
    echo "  1) none"
    echo "  2) 1G"
    echo "  3) 2G"
    echo "  4) 4G"
    printf "Choose [1-4]: "
    read -r ans

    case "$ans" in
      1) printf -v "$__out_var" '%s' "none"; return 0 ;;
      2) printf -v "$__out_var" '%s' "1G";   return 0 ;;
      3) printf -v "$__out_var" '%s' "2G";   return 0 ;;
      4) printf -v "$__out_var" '%s' "4G";   return 0 ;;
      *) echo "Invalid choice. Try again." ;;
    esac
  done
}
