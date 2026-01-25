#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_iface_console() {
  local out_var="$1"
  local default_iface iface

  default_iface="$(iface_detect_default 2>/dev/null || true)"
  [[ -n "$default_iface" ]] || default_iface="ens3"

  echo "Network interface (--iface)"
  echo "  Detected interfaces:"
  if iface_list_candidates | sed 's/^/   - /'; then :; else echo "   (none)"; fi
  echo "  Default: ${default_iface}"
  echo "  Enter 0 to Cancel"

  while true; do
    printf "Interface name [%s]: " "$default_iface"
    read -r iface

    [[ "$iface" == "0" ]] && return 1
    [[ -n "$iface" ]] || iface="$default_iface"

    if iface_exists "$iface"; then
      printf -v "$out_var" '%s' "$iface"
      return 0
    fi

    echo "Invalid interface: '$iface' (not found in /sys/class/net)"
    echo
  done
}
