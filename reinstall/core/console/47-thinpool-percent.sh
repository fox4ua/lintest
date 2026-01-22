#!/usr/bin/env bash
set -Eeuo pipefail

# Thinpool percent of FREE space (only for LVM thin)
# Returns:
#   0 -> ok
#   1 -> cancel
ui_pick_thinpool_percent_console() {
  local out_var="$1"
  local default_percent="95"
  local ans percent

  while true; do
    echo "Thinpool size percent (--thinpool-percent):"
    echo "  1) Use default: ${default_percent}%FREE"
    echo "  2) Enter custom percent"
    echo "  0) Cancel"
    printf "Choose [1-2, 0=Cancel]: "
    read -r ans

    case "$ans" in
      0) return 1 ;;
      1)
        printf -v "$out_var" '%s' "$default_percent"
        return 0
        ;;
      2)
        while true; do
          printf "Enter percent of FREE space for thinpool (1-100, default: %s): " "$default_percent"
          read -r percent
          [[ -n "$percent" ]] || percent="$default_percent"

          if [[ "$percent" =~ ^[0-9]+$ ]] && (( percent >= 1 && percent <= 100 )); then
            printf -v "$out_var" '%s' "$percent"
            return 0
          fi

          echo "Invalid percent. Must be 1..100."
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
