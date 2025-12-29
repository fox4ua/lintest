#!/usr/bin/env bash
set -Eeuo pipefail

detect_boot_mode_strict() {
  if [[ -d /sys/firmware/efi && -d /sys/firmware/efi/efivars ]]; then
    echo "uefi"; return 0
  fi

  if [[ -d /sys/firmware/efi ]]; then
    mkdir -p /sys/firmware/efi/efivars 2>/dev/null || true
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null || true
    if [[ -d /sys/firmware/efi/efivars ]] && ls /sys/firmware/efi/efivars >/dev/null 2>&1; then
      echo "uefi"; return 0
    fi
  fi

  echo "bios"
}

ensure_deps_base() {
  local need=(dialog lsblk parted sgdisk wipefs kpartx udevadm findmnt awk sed grep tar gzip blockdev \
              pvcreate vgcreate lvcreate lvconvert mkfs.ext4 mkswap debootstrap ip curl getent date)

  local missing=()
  for c in "${need[@]}"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done

  if (( ${#missing[@]} > 0 )); then
    stage_set "deps"
    run apt-get update -y
    run apt-get install -y \
      dialog parted gdisk lvm2 debootstrap iproute2 ca-certificates curl wget gnupg \
      tar gzip kpartx udev dnsutils ntpdate psmisc
  fi

  missing=()
  for c in "${need[@]}"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  (( ${#missing[@]} == 0 )) || die "Missing commands after install (base): ${missing[*]}"
}

ensure_deps_uefi() {
  command -v mkfs.vfat >/dev/null 2>&1 && return 0

  stage_set "deps-uefi"
  run apt-get update -y
  run apt-get install -y dosfstools

  command -v mkfs.vfat >/dev/null 2>&1 || die "Missing command after install (uefi): mkfs.vfat"
}
