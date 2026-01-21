#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export BASE_DIR

# Debian install via debootstrap WITHOUT parted/partprobe (uses sgdisk + partx)
#
# Storage modes:
#  - none : ROOT + DATA as partitions (+ optional SWAP as partition)
#  - lvm  : classic LVM
#          vg0/root (fixed ROOT_SIZE)
#          vg0/swap (optional 1/2/4G, NOT thin)
#          vg0/data (rest) -> /var/lib/vz
#  - thin : thin-LVM (recommended layout)
#          vg0/root  : normal LV (fixed ROOT_SIZE, NOT thin)
#          vg0/swap  : normal LV (optional 1/2/4G, NOT thin)
#          vg0/thinpool : ~90% of remaining FREE (leaves headroom)
#          vg0/data  : thin LV inside thinpool -> /var/lib/vz
#
# Options:
#  - /boot size: 256M | 512M | 1G | 2G
#  - swap: none | 1G | 2G | 4G
#  - root size: e.g. 30G
#
# If debootstrap/lvm tools are missing, script will install them using apt-get (from rescue env).
# Destroys ALL data on target disk. Run from rescue/live environment as root.

###############################################################################
# Config (override via env or CLI args)
###############################################################################
DISK="${DISK:-}"
RELEASE="${RELEASE:-bookworm}"              # bullseye|bookworm|trixie|testing|sid
MIRROR="${MIRROR:-http://deb.debian.org/debian}"
HOSTNAME="${HOSTNAME:-debian}"
ARCH="${ARCH:-amd64}"

BOOT_MODE="${BOOT_MODE:-auto}"              # auto|uefi|bios
EFI_SIZE="${EFI_SIZE:-512M}"                # fixed for UEFI
BOOT_SIZE="${BOOT_SIZE:-}"                  # 256M|512M|1G|2G (if empty -> prompt)
SWAP_CHOICE="${SWAP_CHOICE:-}"              # none|1G|2G|4G (if empty -> prompt)
ROOT_SIZE="${ROOT_SIZE:-}"                  # e.g. 30G (if empty -> prompt)

ROOT_FS="${ROOT_FS:-ext4}"                  # ext4|xfs|btrfs
DATA_FS="${DATA_FS:-$ROOT_FS}"              # default same as root

# Storage mode: none|lvm|thin (if empty -> prompt)
LVM_MODE="${LVM_MODE:-}"
VG_NAME="${VG_NAME:-vg0}"
LV_ROOT_NAME="${LV_ROOT_NAME:-root}"
LV_SWAP_NAME="${LV_SWAP_NAME:-swap}"
LV_DATA_NAME="${LV_DATA_NAME:-data}"
THINPOOL_NAME="${THINPOOL_NAME:-thinpool}"
THINPOOL_PCT_FREE="${THINPOOL_PCT_FREE:-90}"  # thinpool = 90%FREE (headroom)

NET_MODE="${NET_MODE:-dhcp}"                # dhcp|static
IFACE="${IFACE:-}"                          # e.g. ens3
IP_ADDR="${IP_ADDR:-}"                      # e.g. 203.0.113.10/24
GW_ADDR="${GW_ADDR:-}"                      # e.g. 203.0.113.1
DNS_ADDR="${DNS_ADDR:-1.1.1.1 8.8.8.8}"
USE_NETWORKD="${USE_NETWORKD:-0}"           # 1 = systemd-networkd, 0 = ifupdown

ROOT_PASS="${ROOT_PASS:-}"                  # if empty -> prompt; empty input locks root
SSH_KEY_FILE="${SSH_KEY_FILE:-}"            # path to public key or authorized_keys for root
TIMEZONE="${TIMEZONE:-UTC}"

TARGET="${TARGET:-/mnt/target}"
LOG_FILE="${LOG_FILE:-/root/debootstrap_install.log}"

ASSUME_YES="${ASSUME_YES:-0}"               # 1 = no destructive confirmation prompt
USE_DIALOG="${USE_DIALOG:-1}"               # 1 = dialog UI if available, 0 = CLI prompts

# libs (step 1)
source "$BASE_DIR/lib/00-env.sh"
source "$BASE_DIR/lib/10-log.sh"
source "$BASE_DIR/lib/15-cli.sh"
source "$BASE_DIR/lib/20-utils.sh"
source "$BASE_DIR/lib/30-prompts.sh"
source "$BASE_DIR/lib/35-preflight.sh"
source "$BASE_DIR/lib/40-disk.sh"
source "$BASE_DIR/lib/45-partition.sh"
source "$BASE_DIR/lib/50-storage.sh"
source "$BASE_DIR/lib/55-mount.sh"
source "$BASE_DIR/lib/10-config.sh"

###############################################################################
# Helpers
###############################################################################
cleanup_secrets() { unset ROOT_PASS || true; }
trap cleanup_secrets EXIT

trap 'on_err $LINENO "$BASH_COMMAND"' ERR

###############################################################################
# CLI parse
###############################################################################
parse_args "$@"

###############################################################################
# Preflight
###############################################################################
umask 077
: >"$LOG_FILE"
chmod 600 "$LOG_FILE"

[[ $EUID -eq 0 ]] || die "Run as root"
[[ -n "${DISK}" ]] || { usage; die "Missing --disk"; }
[[ -b "${DISK}" ]] || die "Not a block device: $DISK"

# Required tools (NO parted / partprobe)
need_cmd lsblk
need_cmd findmnt
need_cmd wipefs
need_cmd sgdisk
need_cmd partx
need_cmd blkid
need_cmd mount
need_cmd umount
need_cmd chroot
need_cmd getent
need_cmd mkfs.ext4
need_cmd passwd
need_cmd chpasswd

case "$ROOT_FS" in
  ext4) need_cmd mkfs.ext4 ;;
  xfs)  need_cmd mkfs.xfs ;;
  btrfs) need_cmd mkfs.btrfs ;;
  *) die "Unsupported ROOT_FS: $ROOT_FS" ;;
esac
case "$DATA_FS" in
  ext4) need_cmd mkfs.ext4 ;;
  xfs)  need_cmd mkfs.xfs ;;
  btrfs) need_cmd mkfs.btrfs ;;
  *) die "Unsupported DATA_FS: $DATA_FS" ;;
esac

# Boot mode
preflight_detect_boot_mode

# Interface
preflight_detect_iface

# Storage mode
if [[ -z "$LVM_MODE" ]]; then prompt_lvm_mode; fi
case "$LVM_MODE" in none|lvm|thin) : ;; *) die "Invalid --lvm-mode: $LVM_MODE (use none|lvm|thin)" ;; esac

# /boot size
if [[ -z "$BOOT_SIZE" ]]; then
  prompt_boot_size
else
  case "$BOOT_SIZE" in 256M|512M|1G|2G) : ;; *) die "Invalid --boot-size: $BOOT_SIZE (use 256M|512M|1G|2G)" ;; esac
fi

# swap
if [[ -z "$SWAP_CHOICE" ]]; then
  prompt_swap_choice
else
  case "$SWAP_CHOICE" in none|1G|2G|4G) : ;; *) die "Invalid --swap: $SWAP_CHOICE (use none|1G|2G|4G)" ;; esac
fi
HAS_SWAP=0
SWAP_SIZE=""
if [[ "$SWAP_CHOICE" != "none" ]]; then
  HAS_SWAP=1
  SWAP_SIZE="$SWAP_CHOICE"
fi

# root size
if [[ -z "$ROOT_SIZE" ]]; then
  while true; do
    read -r -p "Enter ROOT size (e.g. 30G): " ROOT_SIZE
    [[ -n "$ROOT_SIZE" ]] || continue
    valid_size "$ROOT_SIZE" && break
    echo "Bad size format. Use like: 20G, 30G, 512M" >&2
  done
else
  valid_size "$ROOT_SIZE" || die "Invalid --root-size: $ROOT_SIZE (use like 30G)"
fi

# thinpool pct
if ! [[ "$THINPOOL_PCT_FREE" =~ ^[0-9]+$ ]] || (( THINPOOL_PCT_FREE < 50 || THINPOOL_PCT_FREE > 98 )); then
  die "Invalid --thinpool-pct-free: $THINPOOL_PCT_FREE (use integer 50..98)"
fi

# Ensure tools (auto-install)
ensure_debootstrap
ensure_lvm_tools

# Time sanity
preflight_check_time

# DNS/mirror sanity
preflight_check_dns_mirror

# Prevent installing on current root disk
preflight_refuse_if_current_root_disk

# Validate static net
preflight_validate_static_net

# Destructive confirm
log "Selected:"
log "  DISK=$DISK  BOOT_MODE=$BOOT_MODE  RELEASE=$RELEASE  MIRROR=$MIRROR"
log "  HOSTNAME=$HOSTNAME  IFACE=$IFACE  NET_MODE=$NET_MODE  networkd=$USE_NETWORKD"
log "  LVM_MODE=$LVM_MODE  VG=$VG_NAME  ROOT_SIZE=$ROOT_SIZE  BOOT_SIZE=$BOOT_SIZE  SWAP=$SWAP_CHOICE"
log "  ROOT_FS=$ROOT_FS  DATA_FS=$DATA_FS  DATA mount=/var/lib/vz"
if [[ "$LVM_MODE" == "thin" ]]; then
  log "  THINPOOL_PCT_FREE=$THINPOOL_PCT_FREE (thinpool = %FREE)"
fi
confirm "ALL DATA ON $DISK WILL BE DESTROYED. Continue?" || die "Cancelled"

# Root password input (if not provided)
if [[ -z "${ROOT_PASS}" ]]; then
  prompt_root_pass
fi

###############################################################################
# Disk cleanup (best-effort)
###############################################################################
mount_cleanup_target_if_mounted "$TARGET"

log "Releasing locks (best-effort)..."
swapoff -a || true
have_cmd vgchange && vgchange -an >/dev/null 2>&1 || true
have_cmd lvchange && lvchange -an >/dev/null 2>&1 || true
have_cmd mdadm && mdadm --stop --scan >/dev/null 2>&1 || true
have_cmd kpartx && kpartx -d "$DISK" >/dev/null 2>&1 || true

log "Wiping signatures and partition table on $DISK..."
wipefs -a "$DISK"
sgdisk --zap-all "$DISK"

###############################################################################
# Partitioning (GPT) + resolve device paths
###############################################################################
partition_create_gpt
partition_resolve_devices

###############################################################################
# Storage: format boot/efi, create devices (none|lvm|thin), format root/data/swap
###############################################################################
storage_format_boot_efi
storage_format_swap_partition_if_needed
storage_prepare_devices
storage_format_root_data_and_swap

###############################################################################
# Mount target (root + boot + efi + data->/var/lib/vz)
###############################################################################
mount_target_tree
mount_enable_swap

###############################################################################
# Debootstrap
###############################################################################
log "Running debootstrap..."
debootstrap --arch="$ARCH" --variant=minbase "$RELEASE" "$TARGET" "$MIRROR"

###############################################################################
# Base config
###############################################################################
config_write_base

###############################################################################
# Bind mounts for chroot
###############################################################################
mount_chroot_binds

###############################################################################
# Chroot provisioning
###############################################################################
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

###############################################################################
# Set/lock root password (fed via stdin)
###############################################################################
if [[ -n "${ROOT_PASS}" ]]; then
  log "Setting root password..."
  printf 'root:%s\n' "$ROOT_PASS" | chroot "$TARGET" chpasswd
else
  log "Locking root password..."
  chroot "$TARGET" passwd -l root >/dev/null 2>&1 || true
fi
unset ROOT_PASS

###############################################################################
# SSH keys (copy from host)
###############################################################################
if [[ -n "$SSH_KEY_FILE" ]]; then
  log "Installing SSH keys for root from $SSH_KEY_FILE..."
  mkdir -p "$TARGET/root/.ssh"
  chmod 700 "$TARGET/root/.ssh"
  cat "$SSH_KEY_FILE" >>"$TARGET/root/.ssh/authorized_keys"
  chmod 600 "$TARGET/root/.ssh/authorized_keys"
fi

###############################################################################
# Install GRUB
###############################################################################
log "Installing GRUB..."
if [[ "$BOOT_MODE" == "uefi" ]]; then
  chroot "$TARGET" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck --no-nvram
else
  chroot "$TARGET" grub-install --target=i386-pc --recheck "$DISK"
fi
chroot "$TARGET" update-grub

###############################################################################
# Cleanup mounts
###############################################################################
mount_cleanup_all
mount_disable_swap

log "Done. Reboot when ready."
