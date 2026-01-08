#!/usr/bin/env bash

# ui_show_net_current [NET_STACK]
# return: 0=Continue, 1=Cancel/ESC (exit), 2=Back

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
            echo "  IPv4:"
            echo "    address: -"
            echo "    netmask: -"
            echo "    gateway: $gw4"
            echo "    dns: $dns"
          else
            local cidr ip4 p mask idx
            idx=1
            for cidr in "${v4_cidrs[@]}"; do
              ip4="${cidr%/*}"
              p="${cidr#*/}"
              mask="$(net_current_cidr_to_mask "$p")"
              if ((${#v4_cidrs[@]} > 1)); then
                echo "  IPv4 #$idx:"
              else
                echo "  IPv4:"
              fi
              echo "    address: $ip4"
              echo "    netmask: $mask"
              echo "    gateway: $gw4"
              echo "    dns: $dns"
              ((idx++))
            done
          fi

          mapfile -t v6_cidrs < <(ip -o -6 addr show dev "$iface" scope global 2>/dev/null | awk '{print $4}' || true)
          if ((${#v6_cidrs[@]} == 0)); then
            # If no global IPv6, try link-local (useful in many rescues)
            mapfile -t v6_cidrs < <(ip -o -6 addr show dev "$iface" scope link 2>/dev/null | awk '{print $4}' || true)
          fi

          if ((${#v6_cidrs[@]} == 0)); then
            echo "  IPv6:"
            echo "    address: -"
            echo "    prefix: -"
            echo "    gateway: $gw6"
            echo "    dns: $dns"
          else
            local cidr6 ip6 p6 idx6
            idx6=1
            for cidr6 in "${v6_cidrs[@]}"; do
              ip6="${cidr6%/*}"
              p6="${cidr6#*/}"
              if ((${#v6_cidrs[@]} > 1)); then
                echo "  IPv6 #$idx6:"
              else
                echo "  IPv6:"
              fi
              echo "    address: $ip6"
              echo "    prefix: /$p6"
              echo "    gateway: $gw6"
              echo "    dns: $dns"
              ((idx6++))
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

    echo "This is the CURRENT (rescue) config, for reference purposes only."
  } >"$tmp"

  ui_dialog dialog --clear \
    --title "Current network config" \
    --ok-label "Continue" \
    --cancel-label "Back" \
    --extra-button --extra-label "Cancel" \
    --textbox "$tmp" 24 90
  rc=$?
  ui_clear
  rm -f "$tmp" 2>/dev/null || true

  case "$rc" in
    0) return 0 ;;
    3) return 1 ;;     # extra = Cancel
    1|255) return 2 ;; # cancel/esc = Back
    *) return 1 ;;
  esac
}
