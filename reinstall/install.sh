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
source "$BASE_DIR/lib/60-config.sh"
source "$BASE_DIR/lib/65-chroot.sh"
source "$BASE_DIR/lib/70-grub.sh"
source "$BASE_DIR/lib/75-debootstrap.sh"

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
if ! [[ "$THINPOOL_PERCENT" =~ ^[0-9]+$ ]] || (( THINPOOL_PERCENT < 50 || THINPOOL_PERCENT > 98 )); then
  die "Invalid --thinpool-percent: $THINPOOL_PERCENT (use integer 50..98)"
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
  log "  THINPOOL_PERCENT=$THINPOOL_PERCENT (thinpool = %FREE)"
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

log "Releasing locks for $DISK (umount/swapoff/LVM/MD/dm/kpartx)..."
release_disk "$DISK"

log "Wiping signatures and partition table on $DISK..."
disk_wipe_all "$DISK"

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
debootstrap_run

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
chroot_provision_system
chroot_set_root_password
chroot_install_ssh_keys

###############################################################################
# Install GRUB
###############################################################################
grub_install_and_update

###############################################################################
# Cleanup mounts
###############################################################################
mount_cleanup_all
mount_disable_swap

log "Done. Reboot when ready."
