#!/usr/bin/env bash
set -Eeuo pipefail

validate_root_and_disk() {
  [[ $EUID -eq 0 ]] || die "Run as root"
  [[ -n "${DISK}" ]] || { usage; die "Missing --disk"; }
  [[ -b "${DISK}" ]] || die "Not a block device: $DISK"
}

validate_required_tools() {
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
}

validate_filesystems() {
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
}

validate_boot_mode() {
  if [[ "$BOOT_MODE" == "auto" ]]; then
    [[ -d /sys/firmware/efi ]] && BOOT_MODE="uefi" || BOOT_MODE="bios"
  fi
  [[ "$BOOT_MODE" == "uefi" || "$BOOT_MODE" == "bios" ]] || die "BOOT_MODE must be auto|uefi|bios"
}

validate_iface() {
  if [[ -z "$IFACE" ]]; then
    IFACE="$(ip -o link show 2>/dev/null | awk -F': ' '$2 !~ /^(lo|docker|veth|br-|virbr|tun|tap)/ {print $2; exit}')"
  fi
  [[ -n "$IFACE" ]] || die "Could not auto-detect IFACE; set --iface"
}

validate_lvm_mode() {
  if [[ -z "$LVM_MODE" ]]; then prompt_lvm_mode; fi
  case "$LVM_MODE" in none|lvm|thin) : ;; *) die "Invalid --lvm-mode: $LVM_MODE (use none|lvm|thin)" ;; esac
}

validate_boot_size() {
  if [[ -z "$BOOT_SIZE" ]]; then
    prompt_boot_size
  else
    case "$BOOT_SIZE" in 256M|512M|1G|2G) : ;; *) die "Invalid --boot-size: $BOOT_SIZE (use 256M|512M|1G|2G)" ;; esac
  fi
}

validate_swap_choice() {
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
}

validate_root_size() {
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
}

validate_thinpool_pct_free() {
  if ! [[ "$THINPOOL_PCT_FREE" =~ ^[0-9]+$ ]] || (( THINPOOL_PCT_FREE < 50 || THINPOOL_PCT_FREE > 98 )); then
    die "Invalid --thinpool-pct-free: $THINPOOL_PCT_FREE (use integer 50..98)"
  fi
}

validate_static_net() {
  if [[ "$NET_MODE" == "static" ]]; then
    [[ -n "$IP_ADDR" && -n "$GW_ADDR" ]] || die "Static net requires --ip (CIDR) and --gw"
  fi
}

validate_not_current_root_disk() {
  root_src="$(findmnt -no SOURCE / || true)"
  root_base=""
  if [[ -n "$root_src" && -b "$root_src" ]]; then
    root_base="$(lsblk -no PKNAME "$root_src" 2>/dev/null || true)"
  fi
  if [[ -n "$root_base" && "/dev/$root_base" == "$DISK" ]]; then
    die "Refusing to install onto current root disk: $DISK"
  fi
}

validate_dns_and_mirror() {
  log "Checking DNS resolution..."
  getent ahostsv4 deb.debian.org >/dev/null 2>&1 || die "DNS failed for deb.debian.org (fix /etc/resolv.conf in rescue)"
  log "Checking mirror reachability: $MIRROR (release=$RELEASE)"
  fetch_release_file "$MIRROR/dists/$RELEASE/Release" || die "Mirror not reachable or release not found"
}

run_preflight_validation() {
  validate_root_and_disk
  validate_required_tools
  validate_filesystems
  validate_boot_mode
  validate_iface
  validate_lvm_mode
  validate_boot_size
  validate_swap_choice
  validate_root_size
  validate_thinpool_pct_free
  validate_not_current_root_disk
  validate_static_net
}
