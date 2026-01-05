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

# ui_show_net_current [NET_STACK]
# Shows current network configuration (all interfaces) in the current environment.
# return: 0=continue, 1=cancel/esc, 2=back
ui_show_net_current() {
  local net_stack="${1:-}"
  local rc tmp

  tmp="$(mktemp -t net-current.XXXXXX)"
  {
    echo "CURRENT NETWORK CONFIGURATION (rescue environment)"
    if [[ -n "$net_stack" ]]; then
      echo "Selected stack: $net_stack"
    fi
    echo

    echo "=== Links (brief) ==="
    if command -v ip >/dev/null 2>&1; then
      ip -br link 2>/dev/null || true
    else
      echo "ip command not found"
    fi
    echo

    echo "=== Interfaces ==="
    if command -v ip >/dev/null 2>&1; then
      local ifaces iface
      mapfile -t ifaces < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | awk '{print $1}' | sed 's/@.*//' | grep -v '^lo$' || true)

      if ((${#ifaces[@]} == 0)); then
        echo "(no interfaces found)"
      else
        for iface in "${ifaces[@]}"; do
          local dns gw4 gw6
          local v4_cidrs v6_cidrs

          dns="$(net_current_get_dns "$iface")"
          if [[ -z "$dns" ]]; then
            dns="-"
          else
            # Normalize to "a, b, c" for readability.
            local -a dns_a
            local dns_out=""
            read -r -a dns_a <<<"$dns"
            for d in "${dns_a[@]}"; do
              [[ -n "$dns_out" ]] && dns_out+=", "
              dns_out+="$d"
            done
            [[ -n "$dns_out" ]] && dns="$dns_out"
          fi

          gw4="$(net_current_get_gateway4 "$iface")"
          [[ -n "$gw4" ]] || gw4="-"

          gw6="$(net_current_get_gateway6 "$iface")"
          [[ -n "$gw6" ]] || gw6="-"

          echo "[$iface]"

          mapfile -t v4_cidrs < <(ip -o -4 addr show dev "$iface" scope global 2>/dev/null | awk '{print $4}' || true)
          if ((${#v4_cidrs[@]} == 0)); then
            echo "  IPv4: -, -, $gw4, $dns"
          else
            local cidr ip4 p mask
            for cidr in "${v4_cidrs[@]}"; do
              ip4="${cidr%/*}"
              p="${cidr#*/}"
              mask="$(net_current_cidr_to_mask "$p")"
              echo "  IPv4: $ip4, $mask, $gw4, $dns"
            done
          fi

          mapfile -t v6_cidrs < <(ip -o -6 addr show dev "$iface" scope global 2>/dev/null | awk '{print $4}' || true)
          if ((${#v6_cidrs[@]} == 0)); then
            # If no global IPv6, try link-local (useful in many rescues)
            mapfile -t v6_cidrs < <(ip -o -6 addr show dev "$iface" scope link 2>/dev/null | awk '{print $4}' || true)
          fi

          if ((${#v6_cidrs[@]} == 0)); then
            echo "  IPv6: -, -, $gw6, $dns"
          else
            local cidr6 ip6 p6
            for cidr6 in "${v6_cidrs[@]}"; do
              ip6="${cidr6%/*}"
              p6="${cidr6#*/}"
              echo "  IPv6: $ip6, /$p6, $gw6, $dns"
            done
          fi

          echo
        done
      fi
    fi

    echo "=== Routes ==="
    if command -v ip >/dev/null 2>&1; then
      echo "[IPv4]"
      ip -4 route show 2>/dev/null || true
      echo
      echo "[IPv6]"
      ip -6 route show 2>/dev/null || true
    else
      echo "ip command not found"
    fi
    echo

    echo "=== Domain/Search ==="
    local ds_domain ds_search
    local ds_lines
    mapfile -t ds_lines < <(net_current_get_domain_search)
    ds_domain="${ds_lines[0]:-}"
    ds_search="${ds_lines[1]:-}"

    echo "domain: ${ds_domain:-'-'}"
    echo "search: ${ds_search:-'-'}"
    echo

    echo "Tip: this is the CURRENT (rescue) config, not what will be applied after install."
  } >"$tmp"

  ui_dialog dialog --clear \
    --title "Current network config" \
    --ok-label "Continue" \
    --extra-button --extra-label "Cancel" \
    --help-button --help-label "Back" \
    --textbox "$tmp" 24 90
  rc=$?
  ui_clear
  rm -f "$tmp" 2>/dev/null || true

  case "$rc" in
    0) return 0 ;;
    2) return 2 ;;
    3) return 1 ;;     # extra = Cancel
    1|255) return 1 ;;
    *) return 1 ;;
  esac
}
