#!/usr/bin/env bash
set -Eeuo pipefail

# --timezone input
# empty -> default (Europe/Kyiv)
# "0" -> cancel
# Returns: 0 ok, 1 cancel
ui_pick_timezone_console() {
  local out_var="$1"
  local default_tz="Europe/Kyiv"
  local tz

  while true; do
    echo "Timezone (--timezone)"
    echo "  Default: ${default_tz}"
    echo "  Enter 0 to Cancel"
    printf "Timezone [%s]: " "$default_tz"
    read -r tz

    [[ "$tz" == "0" ]] && return 1
    [[ -n "$tz" ]] || tz="$default_tz"

    # validate (zoneinfo exists)
    if [[ -r "/usr/share/zoneinfo/$tz" ]]; then
      printf -v "$out_var" '%s' "$tz"
      return 0
    fi

    echo "Invalid timezone: '$tz' (not found in /usr/share/zoneinfo)"
    echo "Example: Europe/Kyiv, UTC, Europe/Warsaw"
    echo
  done
}
