#!/usr/bin/env bash

# Convert IPv4 CIDR prefix (0-32) to dotted netmask.
net_current_cidr_to_mask() {
  local p="${1:-}"
  [[ "$p" =~ ^[0-9]+$ ]] || { echo "-"; return 0; }

  if (( p <= 0 )); then
    echo "0.0.0.0"
    return 0
  fi
  if (( p >= 32 )); then
    echo "255.255.255.255"
    return 0
  fi

  local mask=$(( (0xffffffff << (32 - p)) & 0xffffffff ))
  printf '%d.%d.%d.%d' \
    $(( (mask >> 24) & 255 )) \
    $(( (mask >> 16) & 255 )) \
    $(( (mask >> 8) & 255 )) \
    $(( mask & 255 ))
}

net_current_get_gateway4() {
  local iface="$1"
  ip -4 route show default dev "$iface" 2>/dev/null | awk '{
    for (i=1;i<=NF;i++) if ($i=="via") {print $(i+1); exit}
  }'
}

net_current_get_gateway6() {
  local iface="$1"
  ip -6 route show default dev "$iface" 2>/dev/null | awk '{
    for (i=1;i<=NF;i++) if ($i=="via") {print $(i+1); exit}
  }'
}

net_current_get_dns() {
  local iface="$1"
  if command -v resolvectl >/dev/null 2>&1; then
    resolvectl dns "$iface" 2>/dev/null | sed -E 's/^Link[[:space:]]+[0-9]+[[:space:]]+\([^)]*\):[[:space:]]*//'
  elif [[ -f /etc/resolv.conf ]]; then
    awk '/^nameserver[[:space:]]+/{print $2}' /etc/resolv.conf 2>/dev/null | tr '\n' ' ' | sed -E 's/[[:space:]]+$//'
  fi
}

net_current_get_domain_search() {
  local domain search
  domain=""
  search=""

  if [[ -f /etc/resolv.conf ]]; then
    domain="$(awk '/^domain[[:space:]]+/{print $2; exit}' /etc/resolv.conf 2>/dev/null)"
    search="$(awk '/^search[[:space:]]+/{for(i=2;i<=NF;i++){printf (i==2?"%s":" %s"),$i} print ""; exit}' /etc/resolv.conf 2>/dev/null)"
  fi

  # If resolv.conf doesn't contain domain/search, try systemd-resolved global domains.
  if [[ -z "$domain" && -z "$search" ]] && command -v resolvectl >/dev/null 2>&1; then
    local gd
    gd="$(resolvectl domain 2>/dev/null | awk -F': ' '/^Global:/{print $2; exit}')"
    # Ignore the special "~." marker if present.
    if [[ -n "$gd" && "$gd" != "~." ]]; then
      search="$gd"
    fi
  fi

  printf '%s\n' "${domain}" "${search}"
}
