#!/usr/bin/env bash

exec_release_disk_mounts() {
  local disk="$1"

  if ! command -v lsblk >/dev/null 2>&1; then
    log "[!] release: lsblk not found, cannot resolve partitions"
    return 1
  fi

  if ! command -v findmnt >/dev/null 2>&1; then
    log "[!] release: findmnt not found, mount cleanup skipped"
    return 1
  fi

  local part target
  while IFS= read -r part; do
    [[ -n "$part" ]] || continue
    while IFS= read -r target; do
      [[ -n "$target" ]] || continue
      log "[=] release: unmounting $target ($part)"
      umount "$target"
    done < <(findmnt -nr -S "$part" -o TARGET 2>/dev/null || true)
  done < <(lsblk -ln -o PATH "$disk" 2>/dev/null | tail -n +2 || true)
}

exec_release_disk_swap() {
  local disk="$1"

  if ! command -v swapon >/dev/null 2>&1; then
    log "[!] release: swapon not found, swap cleanup skipped"
    return 1
  fi

  local swap
  while IFS= read -r swap; do
    [[ -n "$swap" ]] || continue
    if [[ "$swap" == "$disk"* ]]; then
      log "[=] release: swapoff $swap"
      swapoff "$swap"
    fi
  done < <(swapon --show=NAME --noheadings 2>/dev/null | awk '{$1=$1;print}' || true)
}

exec_release_disk_lvm() {
  local disk="$1"

  if ! command -v pvs >/dev/null 2>&1 || ! command -v vgchange >/dev/null 2>&1; then
    log "[!] release: lvm tools not found, LVM cleanup skipped"
    return 1
  fi

  local vg
  while IFS= read -r vg; do
    [[ -n "$vg" ]] || continue
    log "[=] release: deactivating VG $vg"
    vgchange -an "$vg"
  done < <(
    pvs --noheadings -o vg_name,pv_name 2>/dev/null |
      awk -v disk="$disk" '$2 ~ "^"disk {print $1}' |
      awk '{$1=$1;print}' |
      sort -u
  )
}

exec_release_disk_resources() {
  local disk="$1"

  if [[ -z "$disk" ]]; then
    log "[!] release: no disk provided"
    return 1
  fi

  log "[=] release: start for $disk"
  exec_release_disk_mounts "$disk" || true
  exec_release_disk_swap "$disk" || true
  exec_release_disk_lvm "$disk" || true

  if (( DISK_HAS_MD )); then
    log "[!] release: mdraid detected on $disk, manual stop required"
  fi

  log "[=] release: finished for $disk"
}
