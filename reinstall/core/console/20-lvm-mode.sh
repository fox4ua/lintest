#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_lvm_mode_console() {
  local out_var="$1"
  local ans

  while true; do
    echo "Storage layout:"
    echo "  1) No LVM"
    echo "  2) Classic LVM"
    echo "  3) Thin LVM (thinpool for VM)"
    printf "Choose [1-3, 0=Cancel]: "
    read -r ans

    case "$ans" in
      0) return 1 ;;
      1) printf -v "$out_var" '%s' "none"; return 0 ;;
      2) printf -v "$out_var" '%s' "lvm";  return 0 ;;
      3) printf -v "$out_var" '%s' "thin"; return 0 ;;
      *) echo "Invalid choice. Try again." ;;
    esac
  done
}
