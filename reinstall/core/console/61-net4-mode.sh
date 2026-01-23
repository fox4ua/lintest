#!/usr/bin/env bash
set -Eeuo pipefail

# IPv4 network mode (--net4): dhcp|static
# empty -> default (dhcp)
# "0" -> cancel
# Returns: 0 ok, 1 cancel
ui_pick_net4_mode_console() {
  local out_var="$1"
  local default_mode="dhcp"
  local mode

  while true; do
    echo "IPv4 mode (--net4)"
    echo "  Allowed: dhcp | static"
    echo "  Default: ${default_mode}"
    echo "  Enter 0 to Cancel"
    printf "IPv4 mode [%s]: " "$default_mode"
    read -r mode

    [[ "$mode" == "0" ]] && return 1
    [[ -n "$mode" ]] || mode="$default_mode"

    mode="$(echo "$mode" | tr '[:upper:]' '[:lower:]')"

    case "$mode" in
      dhcp|static)
        printf -v "$out_var" '%s' "$mode"
        return 0
        ;;
      *)
        echo "Invalid value. Use: dhcp or static."
        echo
        ;;
    esac
  done
}
