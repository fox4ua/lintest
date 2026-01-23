#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source "$BASE_DIR/init/22-net4-detect.sh"

# --ip input (CIDR), empty -> current/default, "0" -> cancel
ui_pick_net4_ip_console() {
  local out_var="$1"

  local default_ip=""
  local ip_cidr

  [[ -n "${IFACE:-}" ]] || { echo "ERROR: IFACE is not set"; return 1; }

  default_ip="$(net4_detect_ip_cidr "$IFACE" 2>/dev/null || true)"
  [[ -n "$default_ip" ]] || default_ip="203.0.113.10/24"

  while true; do
    echo "IPv4 address (--ip) [static only]"
    echo "  Interface: $IFACE"
    echo "  Default:   $default_ip"
    echo "  Enter 0 to Cancel"
    printf "IP/CIDR [%s]: " "$default_ip"
    read -r ip_cidr

    [[ "$ip_cidr" == "0" ]] && return 1
    [[ -n "$ip_cidr" ]] || ip_cidr="$default_ip"

    if net4_validate_ip_cidr "$ip_cidr"; then
      printf -v "$out_var" '%s' "$ip_cidr"
      return 0
    fi

    echo "Invalid IP/CIDR. Example: 203.0.113.10/24"
    echo
  done
}
