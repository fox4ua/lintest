#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_root_fs_console() {
  local out_var="$1"
  local ans

  while true; do
    echo "Root filesystem (--root-fs):"
    echo "  1) ext4 (default)"
    echo "  2) xfs"
    echo "  3) btrfs"
    printf "Choose [1-3, 0=Cancel]: "
    read -r ans
    
    [[ -n "$ans" ]] || ans="1"

    case "$ans" in
      0) return 1 ;;
      1) printf -v "$out_var" '%s' "ext4"; return 0 ;;
      2) printf -v "$out_var" '%s' "xfs";  return 0 ;;
      3) printf -v "$out_var" '%s' "btrfs";return 0 ;;
      *) echo "Invalid choice. Try again." ;;
    esac
  done
}
