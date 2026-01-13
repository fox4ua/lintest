#!/usr/bin/env bash

cidr_to_netmask4() {
  local cidr="$1"
  local -a octets=()
  local i oct
  for ((i=0; i<4; i++)); do
    if ((cidr >= 8)); then
      oct=255
      cidr=$((cidr - 8))
    elif ((cidr > 0)); then
      oct=$((256 - 2**(8 - cidr)))
      cidr=0
    else
      oct=0
    fi
    octets+=("$oct")
  done
  printf '%s.%s.%s.%s\n' "${octets[0]}" "${octets[1]}" "${octets[2]}" "${octets[3]}"
}

write_hostname_hosts() {
  stage "identity"

  echo "$HOSTNAME_SHORT" >"$TARGET_DIR/etc/hostname"

  local fqdn
  if [[ -n "${HOSTS_FQDN:-}" ]]; then
    fqdn="$HOSTS_FQDN"
  elif [[ -n "${HOSTS_DOMAIN:-}" ]]; then
    fqdn="$HOSTNAME_SHORT.$HOSTS_DOMAIN"
  else
    fqdn="$HOSTNAME_SHORT"
  fi
  cat >"$TARGET_DIR/etc/hosts" <<EOF
127.0.0.1	localhost
127.0.1.1	$fqdn	$HOSTNAME_SHORT

# IPv6
::1	localhost ip6-localhost ip6-loopback
ff02::1	ip6-allnodes
ff02::2	ip6-allrouters
EOF
}

write_network_config() {
  stage "network"

  local iface="$NET_IFACE"
  [[ -n "$iface" ]] || fatal "NET_IFACE is empty"

  case "$NET_STACK" in
    ifupdown)
      cat >"$TARGET_DIR/etc/network/interfaces" <<EOF
auto lo
iface lo inet loopback

auto $iface
EOF

      if [[ "${NET4_ENABLE:-1}" == "1" ]]; then
        if [[ "${NET4_MODE:-dhcp}" == "dhcp" ]]; then
          cat >>"$TARGET_DIR/etc/network/interfaces" <<EOF
iface $iface inet dhcp
EOF
        else
          local ip4="${NET4_ADDR%/*}" cidr4="${NET4_ADDR#*/}"
          local mask4
          mask4="$(cidr_to_netmask4 "$cidr4")"
          cat >>"$TARGET_DIR/etc/network/interfaces" <<EOF
iface $iface inet static
  address $ip4
  netmask $mask4
  gateway $NET4_GW
EOF
        fi
      fi

      if [[ "${NET6_ENABLE:-0}" == "1" ]]; then
        if [[ "${NET6_MODE:-dhcp}" == "dhcp" ]]; then
          cat >>"$TARGET_DIR/etc/network/interfaces" <<EOF
iface $iface inet6 dhcp
EOF
        else
          cat >>"$TARGET_DIR/etc/network/interfaces" <<EOF
iface $iface inet6 static
  address ${NET6_ADDR%/*}
  netmask ${NET6_ADDR#*/}
  gateway $NET6_GW
EOF
        fi
      fi

      if [[ -n "${NET4_DNS:-}" || -n "${NET6_DNS:-}" ]]; then
        local dns_line="${NET4_DNS:-} ${NET6_DNS:-}"
        dns_line="${dns_line# }"
        dns_line="${dns_line% }"
        if [[ -n "$dns_line" ]]; then
          echo "  dns-nameservers $dns_line" >>"$TARGET_DIR/etc/network/interfaces"
        fi
      fi

      write_resolv_conf_fallback
      ;;

    networkd|*)
      mkdir -p "$TARGET_DIR/etc/systemd/network"

      local dhcp="no"
      local v4_dhcp=0
      local v6_dhcp=0
      if [[ "${NET4_ENABLE:-1}" == "1" && "${NET4_MODE:-dhcp}" == "dhcp" ]]; then
        v4_dhcp=1
      fi
      if [[ "${NET6_ENABLE:-0}" == "1" && "${NET6_MODE:-dhcp}" == "dhcp" ]]; then
        v6_dhcp=1
      fi
      if (( v4_dhcp && v6_dhcp )); then
        dhcp="yes"
      elif (( v4_dhcp )); then
        dhcp="ipv4"
      elif (( v6_dhcp )); then
        dhcp="ipv6"
      fi

      cat >"$TARGET_DIR/etc/systemd/network/10-$iface.network" <<EOF
[Match]
Name=$iface

[Network]
DHCP=$dhcp
EOF

      if [[ "${NET4_ENABLE:-1}" == "1" && "${NET4_MODE:-dhcp}" == "static" ]]; then
        cat >>"$TARGET_DIR/etc/systemd/network/10-$iface.network" <<EOF
Address=$NET4_ADDR
Gateway=$NET4_GW
EOF
        for ns in ${NET4_DNS:-}; do
          echo "DNS=$ns" >>"$TARGET_DIR/etc/systemd/network/10-$iface.network"
        done
      fi

      if [[ "${NET6_ENABLE:-0}" == "1" && "${NET6_MODE:-dhcp}" == "static" ]]; then
        cat >>"$TARGET_DIR/etc/systemd/network/10-$iface.network" <<EOF
Address=$NET6_ADDR
Gateway=$NET6_GW
EOF
        for ns in ${NET6_DNS:-}; do
          echo "DNS=$ns" >>"$TARGET_DIR/etc/systemd/network/10-$iface.network"
        done
      fi

      chroot_run "systemctl enable systemd-networkd" || true
      chroot_run "systemctl enable systemd-resolved" || true
      chroot_run "ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf" || true
      ;;
  esac
}

set_root_password() {
  stage "root_pass"
  [[ -n "${ROOT_PASS:-}" ]] || fatal "ROOT_PASS is empty"
  printf 'root:%s\n' "$ROOT_PASS" | chroot_run_quiet "chpasswd"
}
