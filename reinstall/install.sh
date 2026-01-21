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

# libs (step 1)
source "$BASE_DIR/lib/00-env.sh"
source "$BASE_DIR/lib/10-log.sh"
source "$BASE_DIR/lib/15-cli.sh"
source "$BASE_DIR/lib/20-utils.sh"
source "$BASE_DIR/lib/30-prompts.sh"
source "$BASE_DIR/lib/35-preflight.sh"
source "$BASE_DIR/lib/40-disk.sh"

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
log "Unmounting $TARGET if mounted..."
if mountpoint -q "$TARGET"; then
  umount -R "$TARGET" || true
fi

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
# Partitioning (GPT)
# Labels:
#  - none:
#     UEFI: EFI, BOOT, [SWAP], ROOT, DATA
#     BIOS: BIOSBOOT, BOOT, [SWAP], ROOT, DATA
#  - lvm/thin:
#     UEFI: EFI, BOOT, PV
#     BIOS: BIOSBOOT, BOOT, PV
#     (swap is LV inside VG; not a partition)
###############################################################################
log "Creating GPT partitions..."

IS_LVM=0
[[ "$LVM_MODE" != "none" ]] && IS_LVM=1

expected_parts=0
if [[ "$IS_LVM" == "1" ]]; then
  expected_parts=3   # p1 + p2 + pv
else
  expected_parts=$(( 3 + HAS_SWAP ))  # p1 + p2 + root + data (+ swap)
  # without swap: 4 parts; with swap: 5 parts
  expected_parts=$(( expected_parts + 1 )) # add DATA
fi

if [[ "$BOOT_MODE" == "uefi" ]]; then
  if [[ "$IS_LVM" == "1" ]]; then
    sgdisk \
      -n1:1MiB:+${EFI_SIZE}   -t1:EF00 -c1:"EFI" \
      -n2:0:+${BOOT_SIZE}     -t2:8300 -c2:"BOOT" \
      -n3:0:0                 -t3:8E00 -c3:"PV" \
      "$DISK"
  else
    if [[ "$HAS_SWAP" == "1" ]]; then
      sgdisk \
        -n1:1MiB:+${EFI_SIZE} -t1:EF00 -c1:"EFI" \
        -n2:0:+${BOOT_SIZE}   -t2:8300 -c2:"BOOT" \
        -n3:0:+${SWAP_SIZE}   -t3:8200 -c3:"SWAP" \
        -n4:0:+${ROOT_SIZE}   -t4:8300 -c4:"ROOT" \
        -n5:0:0               -t5:8300 -c5:"DATA" \
        "$DISK"
    else
      sgdisk \
        -n1:1MiB:+${EFI_SIZE} -t1:EF00 -c1:"EFI" \
        -n2:0:+${BOOT_SIZE}   -t2:8300 -c2:"BOOT" \
        -n3:0:+${ROOT_SIZE}   -t3:8300 -c3:"ROOT" \
        -n4:0:0               -t4:8300 -c4:"DATA" \
        "$DISK"
    fi
  fi
else
  # BIOS
  if [[ "$IS_LVM" == "1" ]]; then
    sgdisk \
      -n1:1MiB:+1MiB          -t1:EF02 -c1:"BIOSBOOT" \
      -n2:0:+${BOOT_SIZE}     -t2:8300 -c2:"BOOT" \
      -n3:0:0                 -t3:8E00 -c3:"PV" \
      "$DISK"
  else
    if [[ "$HAS_SWAP" == "1" ]]; then
      sgdisk \
        -n1:1MiB:+1MiB        -t1:EF02 -c1:"BIOSBOOT" \
        -n2:0:+${BOOT_SIZE}   -t2:8300 -c2:"BOOT" \
        -n3:0:+${SWAP_SIZE}   -t3:8200 -c3:"SWAP" \
        -n4:0:+${ROOT_SIZE}   -t4:8300 -c4:"ROOT" \
        -n5:0:0               -t5:8300 -c5:"DATA" \
        "$DISK"
    else
      sgdisk \
        -n1:1MiB:+1MiB        -t1:EF02 -c1:"BIOSBOOT" \
        -n2:0:+${BOOT_SIZE}   -t2:8300 -c2:"BOOT" \
        -n3:0:+${ROOT_SIZE}   -t3:8300 -c3:"ROOT" \
        -n4:0:0               -t4:8300 -c4:"DATA" \
        "$DISK"
    fi
  fi
fi

kernel_reread_pt "$DISK" "$expected_parts" || true

# Resolve by labels
P1=""
P_BOOT="$(resolve_part_by_label BOOT)"
P_SWAP=""
P_ROOT=""
P_DATA=""
P_PV=""

if [[ "$BOOT_MODE" == "uefi" ]]; then
  P1="$(resolve_part_by_label EFI)"
else
  P1="$(resolve_part_by_label BIOSBOOT)"
fi

if [[ "$HAS_SWAP" == "1" && "$IS_LVM" == "0" ]]; then
  P_SWAP="$(resolve_part_by_label SWAP)"
fi

if [[ "$IS_LVM" == "1" ]]; then
  P_PV="$(resolve_part_by_label PV)"
else
  P_ROOT="$(resolve_part_by_label ROOT)"
  P_DATA="$(resolve_part_by_label DATA)"
fi

# Fallback mapping by order if labels fail
if [[ -z "$P_BOOT" || ( "$BOOT_MODE" == "uefi" && -z "$P1" ) || ( "$BOOT_MODE" == "bios" && -z "$P1" ) ]]; then
  log "WARN: PARTLABEL resolve incomplete; using lsblk fallback order..."
fi

# Minimal fallback by enumerating parts (order)
mapfile -t _parts < <(list_disk_parts "$DISK")
if [[ "$IS_LVM" == "1" ]]; then
  # p1, p2, pv
  [[ "${#_parts[@]}" -ge 3 ]] || die "Cannot map partitions (expected >=3)"
  P1="${P1:-${_parts[0]}}"
  P_BOOT="${P_BOOT:-${_parts[1]}}"
  P_PV="${P_PV:-${_parts[2]}}"
else
  if [[ "$HAS_SWAP" == "1" ]]; then
    [[ "${#_parts[@]}" -ge 5 ]] || die "Cannot map partitions (expected >=5)"
    P1="${P1:-${_parts[0]}}"
    P_BOOT="${P_BOOT:-${_parts[1]}}"
    P_SWAP="${P_SWAP:-${_parts[2]}}"
    P_ROOT="${P_ROOT:-${_parts[3]}}"
    P_DATA="${P_DATA:-${_parts[4]}}"
  else
    [[ "${#_parts[@]}" -ge 4 ]] || die "Cannot map partitions (expected >=4)"
    P1="${P1:-${_parts[0]}}"
    P_BOOT="${P_BOOT:-${_parts[1]}}"
    P_ROOT="${P_ROOT:-${_parts[2]}}"
    P_DATA="${P_DATA:-${_parts[3]}}"
  fi
fi

# Sanity
[[ -b "$P_BOOT" ]] || die "BOOT partition not found"
if [[ "$BOOT_MODE" == "uefi" ]]; then [[ -b "$P1" ]] || die "EFI partition not found"; fi
if [[ "$BOOT_MODE" == "bios" ]]; then [[ -b "$P1" ]] || die "BIOSBOOT partition not found"; fi
if [[ "$IS_LVM" == "1" ]]; then
  [[ -b "$P_PV" ]] || die "PV partition not found"
else
  [[ -b "$P_ROOT" && -b "$P_DATA" ]] || die "ROOT/DATA partitions not found"
  if [[ "$HAS_SWAP" == "1" ]]; then [[ -b "$P_SWAP" ]] || die "SWAP partition not found"; fi
fi

###############################################################################
# Format EFI/boot + swap partition (only for non-LVM)
###############################################################################
log "Formatting /boot..."
mkfs.ext4 -F -L boot "$P_BOOT"

if [[ "$BOOT_MODE" == "uefi" ]]; then
  need_cmd mkfs.vfat
  log "Formatting EFI..."
  mkfs.vfat -F32 -n EFI "$P1"
fi

if [[ "$IS_LVM" == "0" && "$HAS_SWAP" == "1" ]]; then
  need_cmd mkswap
  log "Creating swap (partition)..."
  mkswap -L swap "$P_SWAP"
fi

###############################################################################
# Prepare root+swap+data devices
###############################################################################
ROOT_DEV=""
DATA_DEV=""
SWAP_DEV=""

if [[ "$IS_LVM" == "0" ]]; then
  ROOT_DEV="$P_ROOT"
  DATA_DEV="$P_DATA"
else
  log "Creating LVM PV/VG on $P_PV..."
  release_disk "$DISK"
  wipefs -a "$P_PV" || true
  pvcreate -ff -y -Z y "$P_PV"
  vgcreate "$VG_NAME" "$P_PV"

  log "Creating root LV: ${VG_NAME}/${LV_ROOT_NAME} size=$ROOT_SIZE (linear)"
  lvcreate -n "$LV_ROOT_NAME" -L "$ROOT_SIZE" "$VG_NAME"
  ROOT_DEV="/dev/${VG_NAME}/${LV_ROOT_NAME}"

  if [[ "$HAS_SWAP" == "1" ]]; then
    need_cmd mkswap
    log "Creating swap LV: ${VG_NAME}/${LV_SWAP_NAME} size=$SWAP_SIZE (linear)"
    lvcreate -n "$LV_SWAP_NAME" -L "$SWAP_SIZE" "$VG_NAME"
    SWAP_DEV="/dev/${VG_NAME}/${LV_SWAP_NAME}"
  fi

  if [[ "$LVM_MODE" == "lvm" ]]; then
    log "Creating data LV: ${VG_NAME}/${LV_DATA_NAME} = 100%FREE (linear)"
    lvcreate -n "$LV_DATA_NAME" -l 100%FREE "$VG_NAME"
    DATA_DEV="/dev/${VG_NAME}/${LV_DATA_NAME}"
  else
    # thin: thinpool ~= 90%FREE, data is thin LV inside
    log "Creating thinpool: ${VG_NAME}/${THINPOOL_NAME} = ${THINPOOL_PCT_FREE}%FREE"
    lvcreate --type thin-pool -n "$THINPOOL_NAME" -l "${THINPOOL_PCT_FREE}%FREE" "$VG_NAME"

    pool_bytes="$(
      LC_ALL=C lvs --noheadings --units B --nosuffix -o LV_SIZE "${VG_NAME}/${THINPOOL_NAME}" \
        | head -n1 \
        | awk '{gsub(/^[ \t]+|[ \t]+$/,""); printf "%.0f\n",$1}'
    )"
    [[ "$pool_bytes" =~ ^[0-9]+$ ]] || die "Cannot parse thinpool size (pool_bytes='$pool_bytes')"

    # Data vsize: almost all pool (leave 128MiB to avoid rounding edge cases)
    reserve=$((128*1024*1024))
    if (( pool_bytes > reserve )); then
      data_vbytes=$(( pool_bytes - reserve ))
    else
      data_vbytes=$pool_bytes
    fi

    log "Creating thin data LV inside thinpool: ${VG_NAME}/${LV_DATA_NAME} vsize=${data_vbytes}B"
    lvcreate -V "${data_vbytes}B" -T "${VG_NAME}/${THINPOOL_NAME}" -n "$LV_DATA_NAME"
    DATA_DEV="/dev/${VG_NAME}/${LV_DATA_NAME}"
  fi
fi

###############################################################################
# Format root + data (swap LV if present)
###############################################################################
log "Formatting root ($ROOT_FS) on $ROOT_DEV..."
case "$ROOT_FS" in
  ext4)  mkfs.ext4 -F -L root "$ROOT_DEV" ;;
  xfs)   mkfs.xfs -f -L root "$ROOT_DEV" ;;
  btrfs) mkfs.btrfs -f -L root "$ROOT_DEV" ;;
esac

log "Formatting data ($DATA_FS) on $DATA_DEV..."
case "$DATA_FS" in
  ext4)  mkfs.ext4 -F -L data "$DATA_DEV" ;;
  xfs)   mkfs.xfs -f -L data "$DATA_DEV" ;;
  btrfs) mkfs.btrfs -f -L data "$DATA_DEV" ;;
esac

if [[ "$IS_LVM" == "1" && "$HAS_SWAP" == "1" ]]; then
  log "Creating swap (LV)..."
  mkswap -L swap "$SWAP_DEV"
fi

###############################################################################
# Mount target (root + boot + efi + data->/var/lib/vz)
###############################################################################
log "Mounting target to $TARGET..."
mkdir -p "$TARGET"
mount "$ROOT_DEV" "$TARGET"

mkdir -p "$TARGET/boot"
mount "$P_BOOT" "$TARGET/boot"

if [[ "$BOOT_MODE" == "uefi" ]]; then
  mkdir -p "$TARGET/boot/efi"
  mount "$P1" "$TARGET/boot/efi"
fi

mkdir -p "$TARGET/var/lib/vz"
mount "$DATA_DEV" "$TARGET/var/lib/vz"

# Enable swap now (partition or LV) so debootstrap has it if needed
if [[ "$HAS_SWAP" == "1" ]]; then
  if [[ "$IS_LVM" == "1" ]]; then
    swapon "$SWAP_DEV" || true
  else
    swapon "$P_SWAP" || true
  fi
fi

###############################################################################
# Debootstrap
###############################################################################
log "Running debootstrap..."
debootstrap --arch="$ARCH" --variant=minbase "$RELEASE" "$TARGET" "$MIRROR"

###############################################################################
# Base config
###############################################################################
log "Writing base config (hostname, hosts, fstab, apt sources)..."
echo "$HOSTNAME" >"$TARGET/etc/hostname"

cat >"$TARGET/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 $HOSTNAME

::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

uuid_root="$(blkid -s UUID -o value "$ROOT_DEV")"
uuid_boot="$(blkid -s UUID -o value "$P_BOOT")"
uuid_data="$(blkid -s UUID -o value "$DATA_DEV")"
uuid_efi=""
uuid_swap=""

if [[ "$BOOT_MODE" == "uefi" ]]; then uuid_efi="$(blkid -s UUID -o value "$P1")"; fi
if [[ "$HAS_SWAP" == "1" ]]; then
  if [[ "$IS_LVM" == "1" ]]; then
    uuid_swap="$(blkid -s UUID -o value "$SWAP_DEV")"
  else
    uuid_swap="$(blkid -s UUID -o value "$P_SWAP")"
  fi
fi

cat >"$TARGET/etc/fstab" <<EOF
UUID=$uuid_root  /           $ROOT_FS  defaults,noatime  0  1
UUID=$uuid_boot  /boot       ext4      defaults,noatime  0  2
UUID=$uuid_data  /var/lib/vz $DATA_FS  defaults,noatime  0  2
EOF

if [[ "$BOOT_MODE" == "uefi" ]]; then
  cat >>"$TARGET/etc/fstab" <<EOF
UUID=$uuid_efi   /boot/efi   vfat      umask=0077       0  1
EOF
fi

if [[ "$HAS_SWAP" == "1" ]]; then
  cat >>"$TARGET/etc/fstab" <<EOF
UUID=$uuid_swap  none        swap      sw              0  0
EOF
fi

components="main contrib non-free"
case "$RELEASE" in
  bookworm|trixie|testing|sid) components="main contrib non-free non-free-firmware" ;;
esac

cat >"$TARGET/etc/apt/sources.list" <<EOF
deb $MIRROR $RELEASE $components
deb $MIRROR $RELEASE-updates $components
deb http://security.debian.org/debian-security $RELEASE-security $components
EOF

###############################################################################
# Bind mounts for chroot
###############################################################################
log "Preparing chroot mounts..."
mount --bind /dev "$TARGET/dev"
mount --bind /dev/pts "$TARGET/dev/pts"
mount -t proc proc "$TARGET/proc"
mount -t sysfs sys "$TARGET/sys"
mount --bind /run "$TARGET/run" || true

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
log "Cleaning up mounts..."
umount -R "$TARGET/dev/pts" || true
umount -R "$TARGET/dev" || true
umount -R "$TARGET/proc" || true
umount -R "$TARGET/sys" || true
umount -R "$TARGET/run" || true
umount -R "$TARGET/boot/efi" || true
umount -R "$TARGET/boot" || true
umount -R "$TARGET/var/lib/vz" || true
umount -R "$TARGET" || true

if [[ "$HAS_SWAP" == "1" ]]; then
  if [[ "$IS_LVM" == "1" ]]; then
    swapoff "/dev/${VG_NAME}/${LV_SWAP_NAME}" || true
  else
    swapoff "$P_SWAP" || true
  fi
fi

log "Done. Reboot when ready."
