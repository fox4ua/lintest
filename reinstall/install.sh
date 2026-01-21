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
source "$BASE_DIR/lib/00-log.sh"


###############################################################################
# Helpers
###############################################################################
have_cmd() { command -v "$1" >/dev/null 2>&1; }
need_cmd() { have_cmd "$1" || die "Missing command: $1"; }

cleanup_secrets() { unset ROOT_PASS || true; }
trap cleanup_secrets EXIT

trap 'on_err $LINENO "$BASH_COMMAND"' ERR

usage() {
  cat <<'EOF'
Usage:
  sudo ./debootstrap-install.sh --disk /dev/sdX [options]

Options:
  --disk /dev/sdX                (required)
  --release bullseye|bookworm|trixie|testing|sid
  --mirror http://deb.debian.org/debian
  --hostname myhost
  --boot-mode auto|uefi|bios

  --lvm-mode none|lvm|thin
  --vg-name vg0
  --root-size 30G
  --boot-size 256M|512M|1G|2G
  --swap none|1G|2G|4G
  --fs ext4|xfs|btrfs
  --data-fs ext4|xfs|btrfs
  --thinpool-pct-free 90         (thinpool = %FREE, default 90)

  --iface ens3
  --net dhcp|static
  --ip 203.0.113.10/24
  --gw 203.0.113.1
  --dns "1.1.1.1 8.8.8.8"
  --networkd 0|1

  --root-pass 'StrongPass'       (optional; if omitted, will prompt; empty locks root)
  --ssh-key-file /path/to/key
  --timezone Europe/Kyiv
  --yes
EOF
}

confirm() {
  local msg="$1"
  if [[ "$ASSUME_YES" == "1" ]]; then
    log "Auto-confirm: $msg"
    return 0
  fi
  read -r -p "$msg [y/N]: " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

prompt_root_pass() {
  local p1 p2
  while true; do
    echo -n "Enter root password (leave empty to LOCK root): " >&2
    IFS= read -r -s p1; echo >&2
    if [[ -z "$p1" ]]; then
      ROOT_PASS=""
      return 0
    fi
    echo -n "Confirm root password: " >&2
    IFS= read -r -s p2; echo >&2
    [[ "$p1" == "$p2" ]] || { echo "Passwords do not match. Try again." >&2; continue; }
    ROOT_PASS="$p1"
    return 0
  done
}


release_disk() {
  local disk="$1"

  # stop typical automounters if present (safe no-op otherwise)
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop udisks2.service 2>/dev/null || true
    systemctl stop udisks2.socket  2>/dev/null || true
  fi

  # swap off anything
  swapoff -a 2>/dev/null || true

  # unmount everything on this disk (including automounts)
  local mp
  while IFS= read -r mp; do
    [[ -n "$mp" ]] || continue
    umount -lf "$mp" 2>/dev/null || true
  done < <(lsblk -lnpo MOUNTPOINTS "$disk" | awk 'NF')

  # deactivate LVM/MD/dm that might hold partitions
  command -v vgchange >/dev/null 2>&1 && vgchange -an  >/dev/null 2>&1 || true
  command -v lvchange >/dev/null 2>&1 && lvchange -an  >/dev/null 2>&1 || true
  command -v mdadm    >/dev/null 2>&1 && mdadm --stop --scan >/dev/null 2>&1 || true
  command -v dmsetup  >/dev/null 2>&1 && dmsetup remove_all >/dev/null 2>&1 || true

  # settle
  command -v partx    >/dev/null 2>&1 && partx -u "$disk" >/dev/null 2>&1 || true
  command -v udevadm  >/dev/null 2>&1 && udevadm settle || true
}


prompt_lvm_mode() {
  local ans
  while true; do
    echo "Select storage mode:"
    echo "  1) без LVM"
    echo "  2) classic LVM"
    echo "  3) тонкий LVM (thin)"
    read -r -p "Choose [1-3]: " ans
    case "$ans" in
      1) LVM_MODE="none"; return 0;;
      2) LVM_MODE="lvm";  return 0;;
      3) LVM_MODE="thin"; return 0;;
      *) echo "Invalid choice. Try again." >&2;;
    esac
  done
}

prompt_boot_size() {
  local ans
  while true; do
    echo "Select /boot size:"
    echo "  1) 256M"
    echo "  2) 512M"
    echo "  3) 1G"
    echo "  4) 2G"
    read -r -p "Choose [1-4]: " ans
    case "$ans" in
      1) BOOT_SIZE="256M"; return 0;;
      2) BOOT_SIZE="512M"; return 0;;
      3) BOOT_SIZE="1G";   return 0;;
      4) BOOT_SIZE="2G";   return 0;;
      *) echo "Invalid choice. Try again." >&2;;
    esac
  done
}

prompt_swap_choice() {
  local ans
  while true; do
    echo "Select swap:"
    echo "  1) без swap"
    echo "  2) 1G"
    echo "  3) 2G"
    echo "  4) 4G"
    read -r -p "Choose [1-4]: " ans
    case "$ans" in
      1) SWAP_CHOICE="none"; return 0;;
      2) SWAP_CHOICE="1G";   return 0;;
      3) SWAP_CHOICE="2G";   return 0;;
      4) SWAP_CHOICE="4G";   return 0;;
      *) echo "Invalid choice. Try again." >&2;;
    esac
  done
}

valid_size() { [[ "$1" =~ ^[0-9]+[kKmMgGtT]$ ]]; }

parse_size_to_bytes() {
  local s="$1" n unit mul
  n="${s%[kKmMgGtT]}"
  unit="${s:${#s}-1:1}"
  case "${unit^^}" in
    K) mul=1024 ;;
    M) mul=$((1024*1024)) ;;
    G) mul=$((1024*1024*1024)) ;;
    T) mul=$((1024*1024*1024*1024)) ;;
    *) die "Bad size unit: $s" ;;
  esac
  echo $(( n * mul ))
}

fetch_release_file() {
  local url="$1"
  if have_cmd curl; then
    curl -fsSL --max-time 10 "$url" >/dev/null
  elif have_cmd wget; then
    wget -qO- --timeout=10 "$url" >/dev/null
  else
    die "Missing command: curl or wget (need one for mirror check)"
  fi
}

ensure_pkg_tools() {
  if ! have_cmd apt-get; then
    die "apt-get not found in rescue env. Use a rescue image with apt-get."
  fi
  if ! have_cmd curl && ! have_cmd wget; then
    log "Installing curl (no curl/wget present)..."
    apt-get update
    apt-get install -y ca-certificates curl
  fi
}

ensure_debootstrap() {
  if have_cmd debootstrap; then return 0; fi
  ensure_pkg_tools
  log "debootstrap not found. Installing debootstrap..."
  apt-get update
  apt-get install -y debootstrap
  have_cmd debootstrap || die "Failed to install debootstrap"
}

ensure_lvm_tools() {
  if [[ "$LVM_MODE" == "none" ]]; then return 0; fi
  if have_cmd pvcreate && have_cmd vgcreate && have_cmd lvcreate && have_cmd lvs && have_cmd vgs; then return 0; fi
  ensure_pkg_tools
  log "LVM tools not found. Installing lvm2..."
  apt-get update
  apt-get install -y lvm2
  have_cmd pvcreate || die "Failed to install lvm2"
}

kernel_reread_pt() {
  local disk="$1"
  local expected="${2:-3}"
  partx -u "$disk" >/dev/null 2>&1 || partx -a "$disk" >/dev/null 2>&1 || true
  have_cmd udevadm && udevadm settle || true

  local i parts_count
  for i in {1..40}; do
    parts_count="$(lsblk -lnpo NAME,TYPE "$disk" 2>/dev/null | awk '$2=="part"{c++} END{print c+0}')"
    [[ "$parts_count" -ge "$expected" ]] && return 0
    sleep 0.2
  done
  return 1
}

resolve_part_by_label() {
  local label="$1"
  blkid -t "PARTLABEL=$label" -o device 2>/dev/null | head -n1 || true
}

list_disk_parts() {
  local disk="$1"
  lsblk -lnpo NAME,TYPE "$disk" 2>/dev/null | awk '$2=="part"{print $1}'
}

###############################################################################
# CLI parse
###############################################################################
while [[ $# -gt 0 ]]; do
  case "$1" in
    --disk) DISK="$2"; shift 2;;
    --release) RELEASE="$2"; shift 2;;
    --mirror) MIRROR="$2"; shift 2;;
    --hostname) HOSTNAME="$2"; shift 2;;
    --boot-mode) BOOT_MODE="$2"; shift 2;;

    --lvm-mode) LVM_MODE="$2"; shift 2;;
    --vg-name) VG_NAME="$2"; shift 2;;
    --root-size) ROOT_SIZE="$2"; shift 2;;
    --boot-size) BOOT_SIZE="$2"; shift 2;;
    --swap) SWAP_CHOICE="$2"; shift 2;;
    --fs) ROOT_FS="$2"; shift 2;;
    --data-fs) DATA_FS="$2"; shift 2;;
    --thinpool-pct-free) THINPOOL_PCT_FREE="$2"; shift 2;;

    --iface) IFACE="$2"; shift 2;;
    --net) NET_MODE="$2"; shift 2;;
    --ip) IP_ADDR="$2"; shift 2;;
    --gw) GW_ADDR="$2"; shift 2;;
    --dns) DNS_ADDR="$2"; shift 2;;
    --networkd) USE_NETWORKD="$2"; shift 2;;

    --root-pass) ROOT_PASS="$2"; shift 2;;
    --ssh-key-file) SSH_KEY_FILE="$2"; shift 2;;
    --timezone) TIMEZONE="$2"; shift 2;;
    --yes) ASSUME_YES="1"; shift 1;;

    -h|--help) usage; exit 0;;
    *) die "Unknown arg: $1";;
  esac
done

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
if [[ "$BOOT_MODE" == "auto" ]]; then
  [[ -d /sys/firmware/efi ]] && BOOT_MODE="uefi" || BOOT_MODE="bios"
fi
[[ "$BOOT_MODE" == "uefi" || "$BOOT_MODE" == "bios" ]] || die "BOOT_MODE must be auto|uefi|bios"

# Interface
if [[ -z "$IFACE" ]]; then
  IFACE="$(ip -o link show 2>/dev/null | awk -F': ' '$2 !~ /^(lo|docker|veth|br-|virbr|tun|tap)/ {print $2; exit}')"
fi
[[ -n "$IFACE" ]] || die "Could not auto-detect IFACE; set --iface"

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

# DNS/mirror sanity
log "Checking DNS resolution..."
getent ahostsv4 deb.debian.org >/dev/null 2>&1 || die "DNS failed for deb.debian.org (fix /etc/resolv.conf in rescue)"
log "Checking mirror reachability: $MIRROR (release=$RELEASE)"
fetch_release_file "$MIRROR/dists/$RELEASE/Release" || die "Mirror not reachable or release not found"

# Prevent installing on current root disk
root_src="$(findmnt -no SOURCE / || true)"
root_base=""
if [[ -n "$root_src" && -b "$root_src" ]]; then
  root_base="$(lsblk -no PKNAME "$root_src" 2>/dev/null || true)"
fi
if [[ -n "$root_base" && "/dev/$root_base" == "$DISK" ]]; then
  die "Refusing to install onto current root disk: $DISK"
fi

# Validate static net
if [[ "$NET_MODE" == "static" ]]; then
  [[ -n "$IP_ADDR" && -n "$GW_ADDR" ]] || die "Static net requires --ip (CIDR) and --gw"
fi

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
