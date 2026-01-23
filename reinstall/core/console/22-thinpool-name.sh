#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_thinpool_name_console() {
  local out_var="$1"
  local default_name="data"
  local name

  while true; do
    echo "Thinpool name (--thinpool-name)"
    echo "  Default: ${default_name}"
    echo "  Enter 0 to Cancel"
    printf "Thinpool name [%s]: " "$default_name"
    read -r name

    [[ "$name" == "0" ]] && return 1
    [[ -n "$name" ]] || name="$default_name"

    if [[ "$name" =~ ^[A-Za-z0-9_][A-Za-z0-9._+-]*$ ]]; then
      printf -v "$out_var" '%s' "$name"
      return 0
    fi

    echo "Invalid name. Allowed: A-Z a-z 0-9 _ . + - (no spaces)."
    echo
  done
}
