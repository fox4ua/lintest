#!/usr/bin/env bash
set -Eeuo pipefail

# Thinpool name (only for LVM thin)
# Returns:
#   0 -> ok
#   1 -> cancel
ui_pick_thinpool_name_console() {
  local out_var="$1"
  local default_name="data"
  local ans name

  while true; do
    echo "Thinpool name (--thinpool-name):"
    echo "  1) Use default: ${default_name}"
    echo "  2) Enter custom name"
    echo "  0) Cancel"
    printf "Choose [1-2, 0=Cancel]: "
    read -r ans

    case "$ans" in
      0) return 1 ;;
      1)
        printf -v "$out_var" '%s' "$default_name"
        return 0
        ;;
      2)
        while true; do
          printf "Enter thinpool name (default: %s): " "$default_name"
          read -r name
          [[ -n "$name" ]] || name="$default_name"

          # allow LV name charset
          if [[ "$name" =~ ^[A-Za-z0-9_][A-Za-z0-9._+-]*$ ]]; then
            printf -v "$out_var" '%s' "$name"
            return 0
          fi

          echo "Invalid name. Allowed: A-Z a-z 0-9 _ . + - (no spaces)."
          echo "  1) Try again"
          echo "  0) Cancel"
          printf "Choose [1, 0=Cancel]: "
          read -r ans
          [[ "$ans" == "0" ]] && return 1
        done
        ;;
      *)
        echo "Invalid choice. Try again."
        ;;
    esac
  done
}
