#!/usr/bin/env bash
set -Eeuo pipefail

net4_detect_ip_cidr() {
  # prints: x.x.x.x/nn (first global inet on iface)
  local iface="$1"
  command -v ip >/dev/null 2>&1 || return 1
  ip -4 addr show dev "$iface" 2>/dev/null \
    | awk '/inet /{print $2; exit}'
}

net4_detect_gw() {
  # prints: x.x.x.x (default gw for iface if present)
  local iface="$1"
  command -v ip >/dev/null 2>&1 || return 1
  ip -4 route show default 2>/dev/null \
    | awk -v ifc="$iface" '($0 ~ (" dev "ifc" ")) {for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}'
}

net4_detect_dns_list() {
  # prints: "1.1.1.1 8.8.8.8" from /etc/resolv.conf
  # (берём все nameserver, сохраняем порядок, удаляем дубли)
  local seen="" ns
  [[ -r /etc/resolv.conf ]] || return 1
  while read -r _ ns _; do
    [[ "$_" == "nameserver" ]] || continue
    [[ "$ns" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || continue
    case " $seen " in
      *" $ns "*) : ;;
      *) seen="${seen}${seen:+ }$ns" ;;
    esac
  done < /etc/resolv.conf
  [[ -n "$seen" ]] || return 1
  printf '%s\n' "$seen"
}

net4_validate_ip_cidr() {
  local v="$1"
  # very practical check: a.b.c.d/nn where nn 0..32
  [[ "$v" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$ ]]
}

net4_validate_ip() {
  local v="$1"
  [[ "$v" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

net4_validate_dns_list() {
  local v="$1" ip
  [[ -n "$v" ]] || return 1
  for ip in $v; do
    net4_validate_ip "$ip" || return 1
  done
  return 0
}
