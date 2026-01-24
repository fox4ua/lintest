#!/usr/bin/env bash
set -Eeuo pipefail

net6_detect_ip_cidr() {
  # prints: xxxx::yyyy/nn (first global inet6 on iface)
  local iface="$1"
  command -v ip >/dev/null 2>&1 || return 1
  ip -6 addr show dev "$iface" 2>/dev/null \
    | awk '/inet6 / && $2 !~ /^fe80:/ {print $2; exit}'
}

net6_detect_gw() {
  # prints: xxxx::1 (default gw for iface if present)
  local iface="$1"
  command -v ip >/dev/null 2>&1 || return 1
  ip -6 route show default 2>/dev/null \
    | awk -v ifc="$iface" '($0 ~ (" dev "ifc" ")) {for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}'
}

net_validate_ip6_cidr() {
  local v="$1"
  # practical (not perfect) check: contains ':' and /0..128
  [[ "$v" == *:*/* ]] || return 1
  [[ "$v" =~ /([0-9]|[1-9][0-9]|1[01][0-9]|12[0-8])$ ]] || return 1
  return 0
}

net_validate_ip6() {
  local v="$1"
  [[ "$v" == *:* ]] || return 1
  return 0
}

net_detect_dns_list_any() {
  # prints: "ip ip ip" (v4/v6), unique, ordered
  local seen="" ns
  [[ -r /etc/resolv.conf ]] || return 1
  while read -r key ns _; do
    [[ "$key" == "nameserver" ]] || continue
    [[ -n "$ns" ]] || continue
    case " $seen " in
      *" $ns "*) : ;;
      *) seen="${seen}${seen:+ }$ns" ;;
    esac
  done < /etc/resolv.conf
  [[ -n "$seen" ]] || return 1
  printf '%s\n' "$seen"
}

net_validate_dns_list_any() {
  local v="$1" ip
  [[ -n "$v" ]] || return 1
  for ip in $v; do
    # allow v4 or v6 (very permissive for v6)
    if [[ "$ip" == *:* ]]; then
      net_validate_ip6 "$ip" || return 1
    else
      [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    fi
  done
  return 0
}
