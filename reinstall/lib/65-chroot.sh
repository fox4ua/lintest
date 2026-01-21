#!/usr/bin/env bash
# shellcheck shell=bash

# Chroot provisioning helpers.
# Requires: log() (lib/00-log.sh)

chroot_provision_system() {
log "Provisioning system inside chroot..."
cat >"$TARGET/root/provision.sh" <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

BOOT_MODE="${BOOT_MODE}"
IFACE="${IFACE}"
NET_MODE="${NET_MODE}"
IP_ADDR="${IP_ADDR}"
GW_ADDR="${GW_ADDR}"
DNS_ADDR="${DNS_ADDR}"
USE_NETWORKD="${USE_NETWORKD}"
TIMEZONE="${TIMEZONE}"
LVM_MODE="${LVM_MODE}"

apt-get update

pkgs=(
  linux-image-amd64
  ca-certificates
  curl
  vim-tiny
  sudo
  locales
  tzdata
  openssh-server
  less
  iproute2
  iputils-ping
  gnupg
)

if [[ "$USE_NETWORKD" == "1" ]]; then
  pkgs+=(systemd-resolved)
else
  pkgs+=(ifupdown)
fi

if [[ "$BOOT_MODE" == "uefi" ]]; then
  pkgs+=(grub-efi-amd64 efibootmgr)
else
  pkgs+=(grub-pc)
fi

if [[ "$LVM_MODE" != "none" ]]; then
  pkgs+=(lvm2)
fi

apt-get install -y "${pkgs[@]}"

# Locale
sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen || true
locale-gen || true
update-locale LANG=en_US.UTF-8 || true

# Timezone
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
dpkg-reconfigure -f noninteractive tzdata || true

# Network config
if [[ "$USE_NETWORKD" == "1" ]]; then
  systemctl enable systemd-networkd
  systemctl enable systemd-resolved

  mkdir -p /etc/systemd/network
  cat >"/etc/systemd/network/10-wan.network" <<EOF
[Match]
Name=$IFACE

[Network]
EOF

  if [[ "$NET_MODE" == "dhcp" ]]; then
    echo "DHCP=yes" >>"/etc/systemd/network/10-wan.network"
  else
    {
      echo "Address=$IP_ADDR"
      echo "Gateway=$GW_ADDR"
      for d in $DNS_ADDR; do echo "DNS=$d"; done
    } >>"/etc/systemd/network/10-wan.network"
  fi

  ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || true
else
  cat >/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto $IFACE
EOF

  if [[ "$NET_MODE" == "dhcp" ]]; then
    cat >>/etc/network/interfaces <<EOF
iface $IFACE inet dhcp
EOF
  else
    addr="${IP_ADDR%/*}"
    cidr="${IP_ADDR#*/}"
    netmask=""
    if command -v python3 >/dev/null 2>&1; then
      netmask="$(python3 - <<PY
import ipaddress
n = ipaddress.IPv4Network("0.0.0.0/" + "$cidr")
print(str(n.netmask))
PY
)"
    fi
    if [[ -z "$netmask" ]]; then
      netmask="255.255.255.0"
      echo "WARN: netmask defaulted to $netmask (install python3 or set manually)" >&2
    fi

    cat >>/etc/network/interfaces <<EOF
iface $IFACE inet static
  address $addr
  netmask $netmask
  gateway $GW_ADDR
  dns-nameservers $DNS_ADDR
EOF
  fi
fi

# SSH: root login via keys by default
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config || true
systemctl enable ssh

# LVM root: update initramfs
if [[ "$LVM_MODE" != "none" ]]; then
  update-initramfs -u -k all || true
fi

apt-get clean
rm -f /root/provision.sh
EOS

chmod +x "$TARGET/root/provision.sh"

chroot "$TARGET" /usr/bin/env \
  BOOT_MODE="$BOOT_MODE" IFACE="$IFACE" NET_MODE="$NET_MODE" \
  IP_ADDR="$IP_ADDR" GW_ADDR="$GW_ADDR" DNS_ADDR="$DNS_ADDR" USE_NETWORKD="$USE_NETWORKD" \
  TIMEZONE="$TIMEZONE" LVM_MODE="$LVM_MODE" \
  /root/provision.sh

}

chroot_set_root_password() {
if [[ -n "${ROOT_PASS}" ]]; then
  log "Setting root password..."
  printf 'root:%s\n' "$ROOT_PASS" | chroot "$TARGET" chpasswd
else
  log "Locking root password..."
  chroot "$TARGET" passwd -l root >/dev/null 2>&1 || true
fi
unset ROOT_PASS
}

chroot_install_ssh_keys() {
if [[ -n "$SSH_KEY_FILE" ]]; then
  log "Installing SSH keys for root from $SSH_KEY_FILE..."
  mkdir -p "$TARGET/root/.ssh"
  chmod 700 "$TARGET/root/.ssh"
  cat "$SSH_KEY_FILE" >>"$TARGET/root/.ssh/authorized_keys"
  chmod 600 "$TARGET/root/.ssh/authorized_keys"
fi
}
