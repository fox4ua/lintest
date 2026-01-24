#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=/dev/null
source "$BASE_DIR/init/23-net6-detect.sh"

ui_pick_net6_ip_console() {
  local out_var="$1"
  local default_ip6=""
  local ip6

  [[ -n "${IFACE:-}" ]] || { echo "ERROR: IFACE is not set"; return 1; }

  default_ip6="$(net6_detect_ip_cidr "$IFACE" 2>/dev/null || true)"
  [[ -n "$default_ip6" ]] || default_ip6="2001:db8::10/64"

  while true; do
    echo "IPv6 address (--ip6) [static only]"
    echo "  Interface: $IFACE"
    echo "  Default:   $default_ip6"
    echo "  Enter 0 to Cancel"
    printf "IPv6/CIDR [%s]: " "$default_ip6"
    read -r ip6

    [[ "$ip6" == "0" ]] && return 1
    [[ -n "$ip6" ]] || ip6="$default_ip6"

    if net_validate_ip6_cidr "$ip6"; then
      printf -v "$out_var" '%s' "$ip6"
      return 0
    fi

    echo "Invalid IPv6/CIDR. Example: 2001:db8::10/64"
    echo
  done
}
