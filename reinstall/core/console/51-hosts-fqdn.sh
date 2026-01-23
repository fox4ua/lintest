#!/usr/bin/env bash
set -Eeuo pipefail

# FQDN for /etc/hosts (optional)
# empty -> no FQDN
# "0" -> cancel
# Returns: 0 ok, 1 cancel
ui_pick_hosts_fqdn_console() {
  local out_var="$1"
  local fqdn

  while true; do
    echo "Hosts: FQDN (optional, for /etc/hosts)"
    echo "  Example: pve.example.com"
    echo "  Default: (empty)"
    echo "  Enter 0 to Cancel"
    printf "FQDN []: "
    read -r fqdn

    [[ "$fqdn" == "0" ]] && return 1
    [[ -n "$fqdn" ]] || { printf -v "$out_var" '%s' ""; return 0; }

    fqdn="$(echo "$fqdn" | tr '[:upper:]' '[:lower:]')"

    # simple FQDN validation:
    # labels: a-z0-9, hyphen inside, 1..63 each, total <=253, at least one dot
    if [[ ${#fqdn} -le 253 ]] && [[ "$fqdn" == *.* ]]; then
      if [[ "$fqdn" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)$ ]]; then
        printf -v "$out_var" '%s' "$fqdn"
        return 0
      fi
    fi

    echo "Invalid FQDN. Example: host.example.com"
    echo
  done
}
