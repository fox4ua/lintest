#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_vg_name_console() {
  local out_var="$1"
  local default_vg="vg0"
  local vg

  while true; do
    echo "LVM Volume Group name (--vg-name)"
    echo "  Default: ${default_vg}"
    echo "  Enter 0 to Cancel"
    printf "VG name [%s]: " "$default_vg"
    read -r vg

    # cancel
    if [[ "$vg" == "0" ]]; then
      return 1
    fi

    # empty -> default
    [[ -n "$vg" ]] || vg="$default_vg"

    # validate: A-Z a-z 0-9 _ . + - (no spaces), first char must be [A-Za-z0-9_]
    if [[ "$vg" =~ ^[A-Za-z0-9_][A-Za-z0-9._+-]*$ ]]; then
      printf -v "$out_var" '%s' "$vg"
      return 0
    fi

    echo "Invalid VG name. Allowed: A-Z a-z 0-9 _ . + - (no spaces)."
    echo
  done
}
