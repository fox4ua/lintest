#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_net6_gw_console() {
  local out_var="$1"
  local default_gw6=""
  local gw6

  [[ -n "${IFACE:-}" ]] || { echo "ERROR: IFACE is not set"; return 1; }

  default_gw6="$(net6_detect_gw "$IFACE" 2>/dev/null || true)"
  [[ -n "$default_gw6" ]] || default_gw6="2001:db8::1"

  while true; do
    echo "IPv6 gateway (--gw6) [static only]"
    echo "  Interface: $IFACE"
    echo "  Default:   $default_gw6"
    echo "  Enter 0 to Cancel"
    printf "Gateway [%s]: " "$default_gw6"
    read -r gw6

    [[ "$gw6" == "0" ]] && return 1
    [[ -n "$gw6" ]] || gw6="$default_gw6"

    if net_validate_ip6 "$gw6"; then
      printf -v "$out_var" '%s' "$gw6"
      return 0
    fi

    echo "Invalid IPv6 gateway. Example: 2001:db8::1"
    echo
  done
}
