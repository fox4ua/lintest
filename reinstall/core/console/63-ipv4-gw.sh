#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source "$BASE_DIR/init/22-net4-detect.sh"

# --gw input, empty -> current/default, "0" -> cancel
ui_pick_net4_gw_console() {
  local out_var="$1"

  local default_gw=""
  local gw

  [[ -n "${IFACE:-}" ]] || { echo "ERROR: IFACE is not set"; return 1; }

  default_gw="$(net4_detect_gw "$IFACE" 2>/dev/null || true)"
  [[ -n "$default_gw" ]] || default_gw="203.0.113.1"

  while true; do
    echo "IPv4 gateway (--gw) [static only]"
    echo "  Interface: $IFACE"
    echo "  Default:   $default_gw"
    echo "  Enter 0 to Cancel"
    printf "Gateway [%s]: " "$default_gw"
    read -r gw

    [[ "$gw" == "0" ]] && return 1
    [[ -n "$gw" ]] || gw="$default_gw"

    if net4_validate_ip "$gw"; then
      printf -v "$out_var" '%s' "$gw"
      return 0
    fi

    echo "Invalid gateway IP. Example: 203.0.113.1"
    echo
  done
}
