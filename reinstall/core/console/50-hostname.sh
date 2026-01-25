#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_hostname_console() {
  local out_var="$1"
  local default_hostname="pve"
  local hn

  while true; do
    echo "Hostname (--hostname)"
    echo "  Default: ${default_hostname}"
    echo "  Enter 0 to Cancel"
    printf "Hostname [%s]: " "$default_hostname"
    read -r hn

    [[ "$hn" == "0" ]] && return 1
    [[ -n "$hn" ]] || hn="$default_hostname"

    # RFC-ish validation (practical):
    # - 1..63 chars
    # - letters/digits/hyphen
    # - cannot start/end with hyphen
    # - lowercase normalization
    hn="$(echo "$hn" | tr '[:upper:]' '[:lower:]')"

    if [[ "$hn" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
      printf -v "$out_var" '%s' "$hn"
      return 0
    fi

    echo "Invalid hostname. Allowed: a-z 0-9 and '-', 1..63 chars, cannot start/end with '-'."
    echo
  done
}
