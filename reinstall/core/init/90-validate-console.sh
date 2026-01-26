#!/usr/bin/env bash
set -Eeuo pipefail

validate_config() {
  [[ -n "$DEBIAN_MIRROR" ]] || die "DEBIAN_MIRROR is empty"
  [[ "$DEBIAN_MIRROR" =~ ^https?://[^[:space:]]+$ ]] || die "Invalid DEBIAN_MIRROR=$DEBIAN_MIRROR"
  if [[ "$LVM_MODE" == "lvm" || "$LVM_MODE" == "thin" ]]; then
    [[ -n "$VG_NAME" ]] || die "VG_NAME is empty (required for LVM/thin)"
    [[ "$VG_NAME" =~ ^[A-Za-z0-9_][A-Za-z0-9._+-]*$ ]] || die "Invalid VG_NAME=$VG_NAME"
  else
    # при no-lvm VG_NAME должен быть пустым
    VG_NAME=""
  fi
  if [[ "$LVM_MODE" == "thin" ]]; then
    [[ -n "$THINPOOL_NAME" ]] || die "THINPOOL_NAME is empty (required for thin)"
    [[ "$THINPOOL_NAME" =~ ^[A-Za-z0-9_][A-Za-z0-9._+-]*$ ]] || die "Invalid THINPOOL_NAME=$THINPOOL_NAME"
    [[ "$THINPOOL_PERCENT" =~ ^[0-9]+$ ]] || die "Invalid THINPOOL_PERCENT=$THINPOOL_PERCENT"
    (( THINPOOL_PERCENT >= 50 && THINPOOL_PERCENT <= 98 )) || die "Invalid THINPOOL_PERCENT=$THINPOOL_PERCENT (expected 50..98)"
  else
    THINPOOL_NAME=""
    THINPOOL_PERCENT=""
  fi
  case "$ROOT_FS" in ext4|xfs|btrfs) :;; *) die "Invalid ROOT_FS=$ROOT_FS";; esac
  [[ -n "$DATA_FS" ]] && case "$DATA_FS" in ext4|xfs|btrfs) :;; *) die "Invalid DATA_FS=$DATA_FS";; esac

  [[ -n "$DEBIAN_MAJOR" ]] || die "DEBIAN_MAJOR is empty"
  [[ -n "$DEBIAN_CODENAME" ]] || die "DEBIAN_CODENAME is empty"

  [[ -n "$BOOT_MODE" ]] || die "BOOT_MODE is empty"
  [[ -n "$DISK" ]] || die "DISK is empty"
  case "$BOOT_MODE" in auto|uefi|bios) :;; *) die "Invalid BOOT_MODE=$BOOT_MODE";; esac
  case "$LVM_MODE" in none|lvm|thin) :;; *) die "Invalid LVM_MODE=$LVM_MODE";; esac
  case "$BOOT_SIZE" in 256|512|1024) :;; *) die "Invalid BOOT_SIZE=$BOOT_SIZE (expected 256/512/1024 MiB)";; esac
  case "$SWAP_SIZE" in 0|1024|2048|4096) :;; *) die "Invalid SWAP_SIZE=$SWAP_SIZE (expected 0/1024/2048/4096 MiB)";; esac
  [[ "$ROOT_SIZE" =~ ^[0-9]+$ ]] || die "Invalid ROOT_SIZE=$ROOT_SIZE (пример: 30)"
  [[ -n "$HOSTNAME" ]] || die "HOSTNAME is empty"
  [[ "$HOSTNAME" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || die "Invalid HOSTNAME=$HOSTNAME"
  if [[ -n "$HOSTS_FQDN" ]]; then
    if [[ ${#HOSTS_FQDN} -le 253 ]] && [[ "$HOSTS_FQDN" == *.* ]]; then
      [[ "$HOSTS_FQDN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)$ ]] || die "Invalid HOSTS_FQDN=$HOSTS_FQDN"
    else
      die "Invalid HOSTS_FQDN=$HOSTS_FQDN"
    fi
  fi
  case "$NET4_MODE" in dhcp|static|off) :;; *) die "Invalid NET4_MODE=$NET4_MODE";; esac
  case "$NET6_MODE" in auto|static|off) :;; *) die "Invalid NET6_MODE=$NET6_MODE";; esac

  if [[ "$NET4_MODE" == "off" && "$NET6_MODE" == "off" ]]; then
    die "Invalid config: NET4_MODE=off requires NET6_MODE!=off"
  fi
  [[ -n "${ROOT_PASS:-}" ]] || die "ROOT_PASS is empty"
}
