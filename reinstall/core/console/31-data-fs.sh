#!/usr/bin/env bash
set -Eeuo pipefail

# Data filesystem: ext4|xfs|btrfs
# Returns:
#   0 -> selected
#   1 -> cancel
ui_pick_data_fs_console() {
  local out_var="$1"
  local default_fs="ext4"
  local ans

  while true; do
    echo "Data filesystem (--data-fs):"
    echo "  1) ext4 (default)"
    echo "  2) xfs"
    echo "  3) btrfs"
    echo "  0) Cancel"
    printf "Choose [1-3, 0=Cancel]: "
    read -r ans

    case "$ans" in
      0) return 1 ;;
      1) printf -v "$out_var" '%s' "ext4"; return 0 ;;
      2) printf -v "$out_var" '%s' "xfs";  return 0 ;;
      3) printf -v "$out_var" '%s' "btrfs";return 0 ;;
      *) echo "Invalid choice. Try again." ;;
    esac
  done
}
