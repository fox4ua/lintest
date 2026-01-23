#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_thinpool_percent_console() {
  local out_var="$1"
  local default_percent="90"
  local percent

  while true; do
    echo "Thinpool size percent (--thinpool-percent)"
    echo "  Default: ${default_percent} (means ${default_percent}%FREE)"
    echo "  Enter 0 to Cancel"
    printf "Percent [1-100] [%s]: " "$default_percent"
    read -r percent

    [[ "$percent" == "0" ]] && return 1
    [[ -n "$percent" ]] || percent="$default_percent"

    if [[ "$percent" =~ ^[0-9]+$ ]] && (( percent >= 1 && percent <= 100 )); then
      printf -v "$out_var" '%s' "$percent"
      return 0
    fi

    echo "Invalid percent. Must be 1..100."
    echo
  done
}
