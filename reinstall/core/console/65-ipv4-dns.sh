#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_net4_dns_console() {
  local out_var="$1"

  local default_dns=""
  local dns

  default_dns="$(net4_detect_dns_list 2>/dev/null || true)"
  [[ -n "$default_dns" ]] || default_dns="1.1.1.1 8.8.8.8"

  while true; do
    echo "DNS servers (--dns) [static only]"
    echo "  Default: ${default_dns}"
    echo "  Enter 0 to Cancel"
    printf 'DNS (space-separated) [%s]: ' "$default_dns"
    read -r dns

    [[ "$dns" == "0" ]] && return 1
    [[ -n "$dns" ]] || dns="$default_dns"

    if net4_validate_dns_list "$dns"; then
      printf -v "$out_var" '%s' "$dns"
      return 0
    fi

    echo 'Invalid DNS list. Example: 1.1.1.1 8.8.8.8'
    echo
  done
}
