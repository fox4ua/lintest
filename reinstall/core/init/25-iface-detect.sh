#!/usr/bin/env bash
set -Eeuo pipefail

iface_list_candidates() {
  local i
  for i in /sys/class/net/*; do
    i="$(basename "$i")"
    [[ "$i" == "lo" ]] && continue
    printf '%s\n' "$i"
  done
}

iface_detect_default() {
  # 1) default route
  if command -v ip >/dev/null 2>&1; then
    local dev
    dev="$(ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' || true)"
    [[ -n "$dev" ]] && { printf '%s\n' "$dev"; return 0; }
  fi

  # 2) first non-lo
  iface_list_candidates | head -n1
}

iface_exists() {
  local iface="$1"
  [[ -n "$iface" && -d "/sys/class/net/$iface" ]]
}
