#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_debian_mirror_console() {
  local out_var="$1"
  local default_mirror="http://deb.debian.org/debian"
  local mirror

  while true; do
    echo "Debian mirror (--mirror)"
    echo "  Default: ${default_mirror}"
    echo "  Enter 0 to Cancel"
    printf "Mirror URL [%s]: " "$default_mirror"
    read -r mirror

    [[ "$mirror" == "0" ]] && return 1
    [[ -n "$mirror" ]] || mirror="$default_mirror"

    if [[ "$mirror" =~ ^https?://[^[:space:]]+$ ]]; then
      printf -v "$out_var" '%s' "$mirror"
      return 0
    fi

    echo "Invalid URL. Must start with http:// or https:// and contain no spaces."
    echo
  done
}
