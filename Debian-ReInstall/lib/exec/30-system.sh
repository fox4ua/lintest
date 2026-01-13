#!/usr/bin/env bash

debootstrap_install() {
  stage "debootstrap"

  mkdir -p "$TARGET_DIR"

  local arch
  arch="$(dpkg --print-architecture 2>/dev/null || true)"
  if [[ -z "$arch" ]]; then
    case "$(uname -m 2>/dev/null || true)" in
      x86_64) arch="amd64" ;;
      i386|i686) arch="i386" ;;
      aarch64) arch="arm64" ;;
      armv7l) arch="armhf" ;;
      ppc64le) arch="ppc64el" ;;
      s390x) arch="s390x" ;;
    esac
  fi
  [[ -n "$arch" ]] || fatal "Unable to detect target architecture for debootstrap"

  run debootstrap --arch "$arch" "$DEBIAN_SUITE" "$TARGET_DIR" "$DEBIAN_MIRROR"
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
      comps="main contrib non-free non-free-firmware"
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
  exec_net_check_target
  if [[ -n "${NET4_DNS:-}" || -n "${NET6_DNS:-}" ]]; then
    write_resolv_conf_fallback
  else
    write_host_resolv_conf
  fi
  ensure_target_nsswitch_dns

  # Ensure apt works
  if ! chroot_apt_update; then
    log "[!] apt-get update failed; current target resolv.conf:"
    log_target_resolv_conf
    log "[!] apt-get update failed; retrying with fallback DNS."
    write_resolv_conf_defaults
    log "[!] retrying apt-get update with fallback resolv.conf:"
    log_target_resolv_conf
    chroot_apt_update || fatal "apt-get update failed after retry (check network/DNS)."
  fi

  local arch grub_pkg kernel_pkg
  arch="$(dpkg --print-architecture 2>/dev/null || true)"
  if [[ -z "$arch" ]]; then
    case "$(uname -m 2>/dev/null || true)" in
      x86_64) arch="amd64" ;;
      i386|i686) arch="i386" ;;
      aarch64) arch="arm64" ;;
      armv7l) arch="armhf" ;;
      ppc64le) arch="ppc64el" ;;
      s390x) arch="s390x" ;;
    esac
  fi
  [[ -n "$arch" ]] || fatal "Unable to detect target architecture for package install"

  case "$arch" in
    amd64) kernel_pkg="linux-image-amd64" ;;
    i386) kernel_pkg="linux-image-686-pae" ;;
    arm64) kernel_pkg="linux-image-arm64" ;;
    armhf) kernel_pkg="linux-image-armmp" ;;
    ppc64el) kernel_pkg="linux-image-ppc64el" ;;
    s390x) kernel_pkg="linux-image-s390x" ;;
    *) kernel_pkg="linux-image-$arch" ;;
  esac

  case "$BOOT_MODE" in
    uefi)
      grub_pkg="grub-efi-$arch"
      ;;
    *)
      case "$arch" in
        amd64|i386) grub_pkg="grub-pc" ;;
        *) grub_pkg="grub-efi-$arch" ;;
      esac
      ;;
  esac

  local net_pkgs="" dhcp_pkg=""
  case "$NET_STACK" in
    ifupdown) net_pkgs="ifupdown" ;;
    networkd|*) net_pkgs="" ;;
  esac

  if [[ "$NET_STACK" == "ifupdown" ]]; then
    if [[ "${NET4_ENABLE:-1}" == "1" && "${NET4_MODE:-dhcp}" == "dhcp" ]]; then
      dhcp_pkg="isc-dhcp-client"
    fi
    if [[ "${NET6_ENABLE:-0}" == "1" && "${NET6_MODE:-dhcp}" == "dhcp" ]]; then
      dhcp_pkg="isc-dhcp-client"
    fi
  fi

  local lvm_pkgs=""
  [[ "$LVM_MODE" != "none" ]] && lvm_pkgs="lvm2"



  chroot_run "apt-get install -y --no-install-recommends ca-certificates systemd-sysv $kernel_pkg $grub_pkg $net_pkgs $dhcp_pkg $lvm_pkgs"
}

log_target_resolv_conf() {
  if [[ -f "$TARGET_DIR/etc/resolv.conf" ]]; then
    sed 's/^/[debug] /' "$TARGET_DIR/etc/resolv.conf" >>"$LOG_FILE"
  else
    log "[debug] $TARGET_DIR/etc/resolv.conf is missing"
  fi
}

chroot_apt_update() {
  local output
  output="$(mktemp -t apt-update.XXXXXX)"
  log "[chroot] apt-get update"
  chroot "$TARGET_DIR" /usr/bin/env -i \
    HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    DEBIAN_FRONTEND=noninteractive \
    bash -lc "apt-get update -o Acquire::Retries=3" >"$output" 2>&1
  local rc=$?
  cat "$output" >>"$LOG_FILE"
  if grep -Eq 'Temporary failure resolving|Failed to fetch|Could not resolve|No address associated with hostname' "$output"; then
    rc=1
  fi
  rm -f "$output"
  return $rc
}

write_hostname_hosts() {
  stage "identity"

  echo "$HOSTNAME_SHORT" >"$TARGET_DIR/etc/hostname"

  # hosts
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

write_resolv_conf_fallback() {
  # For ifupdown or static DNS fallback.
  prepare_target_resolv_conf
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


host_resolv_conf_source() {
  local -a candidates=()

  if [[ -e /etc/resolv.conf ]]; then
    if grep -qE '^\s*nameserver\s+127\.0\.0\.53(\s|$)' /etc/resolv.conf; then
      candidates+=(/run/systemd/resolve/resolv.conf)
      candidates+=(/run/NetworkManager/resolv.conf)
      candidates+=(/run/resolvconf/resolv.conf)
    else
      candidates+=(/etc/resolv.conf)
      candidates+=(/run/systemd/resolve/resolv.conf)
      candidates+=(/run/NetworkManager/resolv.conf)
      candidates+=(/run/resolvconf/resolv.conf)
    fi
  else
    candidates+=(/run/systemd/resolve/resolv.conf)
    candidates+=(/run/NetworkManager/resolv.conf)
    candidates+=(/run/resolvconf/resolv.conf)
  fi

  for src in "${candidates[@]}"; do
    if [[ -e "$src" ]] && grep -qE '^\s*nameserver\s+' "$src"; then
      echo "$src"
      return 0
    fi
  done
  return 1
}

write_host_resolv_conf() {
  prepare_target_resolv_conf
  local src=""
  local dns=""
  local -a dns_list=()

  if src="$(host_resolv_conf_source)"; then
    :
  else
    src=""
  fi

  if [[ -n "$src" ]]; then
    cp -f "$src" "$TARGET_DIR/etc/resolv.conf"
    return 0
  fi

  if [[ -n "${NET_IFACE:-}" ]]; then
    dns="$(net_current_get_dns "$NET_IFACE" || true)"
  fi

  if [[ -n "$dns" ]]; then
    for ns in $dns; do
      [[ "$ns" == "127.0.0.53" ]] && continue
      dns_list+=("$ns")
    done
  fi

  if [[ ${#dns_list[@]} -eq 0 ]]; then
    while IFS= read -r ns; do
      dns_list+=("$ns")
    done < <(get_fallback_dns_list)
  fi

  {
    for ns in "${dns_list[@]}"; do
      echo "nameserver $ns"
    done
  } >"$TARGET_DIR/etc/resolv.conf"
}

write_resolv_conf_defaults() {
  rm -f "$TARGET_DIR/etc/resolv.conf"
  cat >"$TARGET_DIR/etc/resolv.conf" <<'EOF'
options timeout:1 attempts:2 rotate
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 2606:4700:4700::1111
nameserver 2001:4860:4860::8888
EOF
}


get_fallback_dns_list() {
  local -a dns_list=()
  local -a host_dns=()

  if [[ -n "${NET_FALLBACK_DNS:-}" ]]; then
    for ns in $NET_FALLBACK_DNS; do
      dns_list+=("$ns")
    done
  else
    while IFS= read -r ns; do
      host_dns+=("$ns")
    done < <(get_host_nameservers)

    dns_list+=("${host_dns[@]}")
    dns_list+=("1.1.1.1" "8.8.8.8")
    if [[ "${NET6_ENABLE:-0}" == "1" ]]; then
      dns_list+=("2606:4700:4700::1111" "2001:4860:4860::8888")
    fi
  fi

  printf '%s\n' "${dns_list[@]}" | awk '!seen[$0]++'
}

prepare_target_resolv_conf() {
  mkdir -p "$TARGET_DIR/etc"
  if [[ -L "$TARGET_DIR/etc/resolv.conf" ]]; then
    rm -f "$TARGET_DIR/etc/resolv.conf"
  fi
}


get_host_nameservers() {
  local src=""

  if src="$(host_resolv_conf_source)"; then
    :
  else
    src=""
  fi

  if [[ -n "$src" ]]; then
    awk '/^nameserver[[:space:]]+/{print $2}' "$src" 2>/dev/null | awk '$1!="127.0.0.53"'
  fi
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

      # Enable networkd/resolved
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
