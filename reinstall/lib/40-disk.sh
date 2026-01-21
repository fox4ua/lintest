#!/usr/bin/env bash
# shellcheck shell=bash

# Disk / partition helper functions.
#
# Depends on: have_cmd() from lib/01-utils.sh

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
  command -v kpartx   >/dev/null 2>&1 && kpartx -d "$disk" >/dev/null 2>&1 || true

  # settle
  command -v partx    >/dev/null 2>&1 && partx -u "$disk" >/dev/null 2>&1 || true
  command -v udevadm  >/dev/null 2>&1 && udevadm settle || true
}

disk_wipe_all() {
  local disk="$1"
  wipefs -a "$disk"
  sgdisk --zap-all "$disk"
  command -v partx   >/dev/null 2>&1 && partx -u "$disk" >/dev/null 2>&1 || true
  command -v udevadm >/dev/null 2>&1 && udevadm settle || true
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

