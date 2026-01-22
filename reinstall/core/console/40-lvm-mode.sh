#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_lvm_mode_console() {
  local __out_var="$1"
  local ans

  while true; do
    echo "Storage layout:"
    echo "  1) No LVM"
    echo "  2) Classic LVM"
    echo "  3) Thin LVM (thinpool)"
    printf "Choose [1-3]: "
    read -r ans

    case "$ans" in
      1) printf -v "$__out_var" '%s' "none"; return 0 ;;
      2) printf -v "$__out_var" '%s' "lvm";  return 0 ;;
      3) printf -v "$__out_var" '%s' "thin"; return 0 ;;
      *) echo "Invalid choice. Try again." ;;
    esac
  done
}
