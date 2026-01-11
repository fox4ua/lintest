#!/usr/bin/env bash

debootstrap_install() {
  stage "debootstrap"

  mkdir -p "$TARGET_DIR"

  run debootstrap --arch amd64 "$DEBIAN_SUITE" "$TARGET_DIR" "$DEBIAN_MIRROR"
}

cidr_to_netmask4() {
  # Input: 0..32
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

write_sources_list() {
  stage "apt_sources"

  local comps
  case "$DEBIAN_SUITE" in
    bullseye)
      comps="main contrib non-free"
      ;;
    bookworm|trixie|*)
      comps="main contrib non-free-firmware"
      ;;
  esac

  mkdir -p "$TARGET_DIR/etc/apt"
  cat >"$TARGET_DIR/etc/apt/sources.list" <<EOF
deb $DEBIAN_MIRROR $DEBIAN_SUITE $comps
deb $DEBIAN_MIRROR $DEBIAN_SUITE-updates $comps
deb http://security.debian.org/debian-security $DEBIAN_SUITE-security $comps
EOF
}

install_base_packages() {
  stage "apt_install"

  mount_chroot_helpers

  # Ensure apt works
  chroot_run "apt-get update"

  local grub_pkg kernel_pkg
  kernel_pkg="linux-image-amd64"

  case "$BOOT_MODE" in
    uefi)
      grub_pkg="grub-efi-amd64"
      ;;
    *)
      grub_pkg="grub-pc"
      ;;
  esac

  local net_pkgs=""
  case "$NET_STACK" in
    ifupdown) net_pkgs="ifupdown" ;;
    networkd|*) net_pkgs="" ;;
  esac

  local lvm_pkgs=""
  [[ "$LVM_MODE" != "none" ]] && lvm_pkgs="lvm2"

  chroot_run "apt-get install -y --no-install-recommends ca-certificates systemd-sysv $kernel_pkg $grub_pkg $net_pkgs $lvm_pkgs"
}

write_hostname_hosts() {
  stage "identity"

  echo "$HOSTNAME_SHORT" >"$TARGET_DIR/etc/hostname"

  # hosts
  local fqdn="${HOSTS_FQDN:-$HOSTNAME_SHORT.$HOSTS_DOMAIN}"
  cat >"$TARGET_DIR/etc/hosts" <<EOF
127.0.0.1	localhost
127.0.1.1	$fqdn	$HOSTNAME_SHORT

# IPv6
::1	localhost ip6-localhost ip6-loopback
ff02::1	ip6-allnodes
ff02::2	ip6-allrouters
EOF
}

write_resolv_conf_fallback() {
  # For ifupdown or static DNS fallback.
  local dns=""
  if [[ "${NET4_ENABLE:-1}" == "1" && -n "${NET4_DNS:-}" ]]; then
    dns+=" ${NET4_DNS}"
  fi
  if [[ "${NET6_ENABLE:-0}" == "1" && -n "${NET6_DNS:-}" ]]; then
    dns+=" ${NET6_DNS}"
  fi
  dns="${dns# }"
  [[ -n "$dns" ]] || return 0

  {
    for ns in $dns; do
      echo "nameserver $ns"
    done
  } >"$TARGET_DIR/etc/resolv.conf"
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
          # NET4_ADDR format: a.b.c.d/nn
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

      write_resolv_conf_fallback
      ;;

    networkd|*)
      mkdir -p "$TARGET_DIR/etc/systemd/network"

      local dhcp="no"
      if [[ "${NET4_ENABLE:-1}" == "1" && "${NET4_MODE:-dhcp}" == "dhcp" && "${NET6_ENABLE:-0}" != "1" ]]; then
        dhcp="ipv4"
      elif [[ "${NET6_ENABLE:-0}" == "1" && "${NET6_MODE:-dhcp}" == "dhcp" && "${NET4_ENABLE:-1}" != "1" ]]; then
        dhcp="ipv6"
      elif [[ "${NET4_ENABLE:-1}" == "1" && "${NET4_MODE:-dhcp}" == "dhcp" && "${NET6_ENABLE:-0}" == "1" && "${NET6_MODE:-dhcp}" == "dhcp" ]]; then
        dhcp="yes"
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

      # Enable networkd
      chroot_run "systemctl enable systemd-networkd" || true
      ;;
  esac
}

set_root_password() {
  stage "root_pass"
  [[ -n "${ROOT_PASS:-}" ]] || fatal "ROOT_PASS is empty"
  chroot_run "echo 'root:${ROOT_PASS}' | chpasswd"
}
