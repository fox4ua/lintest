#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_net6_mode_console() {
  local out_var="$1"
  local default_mode="auto"
  local mode
  local forbid_off="${NET6_FORBID_OFF:-0}"

  while true; do
    echo "IPv6 mode (--net6)"
    if [[ "$forbid_off" == "1" ]]; then
      echo "  Allowed: auto | static"
      echo "  Note: 'off' is not allowed because IPv4 is OFF."
    else
      echo "  Allowed: auto | static | off"
    fi
    echo "  Default: ${default_mode}"
    echo "  Enter 0 to Cancel"
    printf "IPv6 mode [%s]: " "$default_mode"
    read -r mode

    [[ "$mode" == "0" ]] && return 1
    [[ -n "$mode" ]] || mode="$default_mode"

    mode="$(echo "$mode" | tr '[:upper:]' '[:lower:]')"

    if [[ "$forbid_off" == "1" && "$mode" == "off" ]]; then
      echo "Invalid: 'off' is not allowed when IPv4 is OFF. Use auto or static."
      echo
      continue
    fi

    case "$mode" in
      auto|static|off)
        printf -v "$out_var" '%s' "$mode"
        return 0
        ;;
      *)
        if [[ "$forbid_off" == "1" ]]; then
          echo "Invalid value. Use: auto or static."
        else
          echo "Invalid value. Use: auto, static or off."
        fi
        echo
        ;;
    esac
  done
}
