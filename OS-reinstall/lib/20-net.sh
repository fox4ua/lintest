#!/usr/bin/env bash
set -Eeuo pipefail

cidr_to_netmask() {
  local cidr="$1"
  (( cidr >= 0 && cidr <= 32 )) || die "CIDR out of range: $cidr"
  local full=$(( cidr / 8 )) rem=$(( cidr % 8 )) i oct mask=""
  for ((i=0;i<4;i++)); do
    if (( i < full )); then
      oct=255
    elif (( i == full )); then
      if (( rem == 0 )); then oct=0; else oct=$(( 256 - (2 ** (8 - rem)) )); fi
    else
      oct=0
    fi
    mask+="$oct"
    (( i < 3 )) && mask+="."
  done
  echo "$mask"
}

net_write_ifupdown() {
  local iface="$1" mode="$2" profile="$3" data="$4"

  log "Writing ifupdown config for ${iface}"

  if [[ "$mode" == "dhcp" ]]; then
    cat > /mnt/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

allow-hotplug ${iface}
iface ${iface} inet dhcp
EOF
    return 0
  fi

  if [[ "$profile" == "ovh32" ]]; then
    IFS='|' read -r ip gw dns <<<"$data"

    cat > /mnt/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

allow-hotplug ${iface}
iface ${iface} inet static
  address ${ip}
  netmask 255.255.255.255
  gateway ${gw}
  post-up ip route add ${gw} dev ${iface} || true
  post-up ip route replace default via ${gw} dev ${iface} onlink || true
  pre-down ip route del default via ${gw} dev ${iface} || true
EOF

    : > /mnt/etc/resolv.conf
    for ns in ${dns}; do
      echo "nameserver ${ns}" >> /mnt/etc/resolv.conf
    done
    return 0
  fi

  IFS='|' read -r ipcidr gw dns <<<"$data"
  local ip="${ipcidr%/*}"
  local cidr="${ipcidr#*/}"
  local mask; mask="$(cidr_to_netmask "$cidr")"

  cat > /mnt/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

allow-hotplug ${iface}
iface ${iface} inet static
  address ${ip}
  netmask ${mask}
  gateway ${gw}
EOF

  : > /mnt/etc/resolv.conf
  for ns in ${dns}; do
    echo "nameserver ${ns}" >> /mnt/etc/resolv.conf
  done
}

net_write_networkd() {
  local iface="$1" mode="$2" profile="$3" data="$4"

  log "Writing systemd-networkd config for ${iface}"

  mkdir -p /mnt/etc/systemd/network
  mkdir -p /mnt/etc/systemd/resolved.conf.d

  if [[ "$mode" == "dhcp" ]]; then
    cat > /mnt/etc/systemd/network/10-wan.network <<EOF
[Match]
Name=${iface}

[Network]
DHCP=yes
IPv6AcceptRA=no
EOF
    return 0
  fi

  if [[ "$profile" == "ovh32" ]]; then
    IFS='|' read -r ip gw dns <<<"$data"

    cat > /mnt/etc/systemd/network/10-wan.network <<EOF
[Match]
Name=${iface}

[Network]
Address=${ip}/32
DNS=${dns}
IPv6AcceptRA=no

[Route]
Destination=0.0.0.0/0
Gateway=${gw}
GatewayOnLink=yes
EOF
    return 0
  fi

  IFS='|' read -r ipcidr gw dns <<<"$data"

  cat > /mnt/etc/systemd/network/10-wan.network <<EOF
[Match]
Name=${iface}

[Network]
Address=${ipcidr}
Gateway=${gw}
DNS=${dns}
IPv6AcceptRA=no
EOF
}
