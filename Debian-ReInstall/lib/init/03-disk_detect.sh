#!/usr/bin/env bash

disk_is_current_env_disk() {
  local disk="$1"
  local src

  src="$(findmnt -no SOURCE / 2>/dev/null || true)"
  [[ -n "$src" && "$src" == "$disk"* ]] && return 0

  src="$(findmnt -no SOURCE /boot 2>/dev/null || true)"
  [[ -n "$src" && "$src" == "$disk"* ]] && return 0

  src="$(findmnt -no SOURCE /boot/efi 2>/dev/null || true)"
  [[ -n "$src" && "$src" == "$disk"* ]] && return 0

  return 1
}

disk_detect_usage_flags() {
  local disk="$1"
  DISK_HAS_MOUNTS=0
  DISK_HAS_SWAP=0
  DISK_HAS_LVM=0
  DISK_HAS_MD=0
  DISK_NEEDS_RELEASE=0
  local parts
  parts="$(lsblk -ln -o PATH "$disk" 2>/dev/null | tail -n +2 || true)"

  # mounts
  if [[ -n "$parts" ]]; then
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      if findmnt -nr -S "$p" >/dev/null 2>&1; then
        DISK_HAS_MOUNTS=1
        DISK_NEEDS_RELEASE=1
        break
      fi
    done <<<"$parts"
  fi

  # swap
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    if [[ "$s" == "$disk"* ]]; then
      DISK_HAS_SWAP=1
      DISK_NEEDS_RELEASE=1
      break
    fi
  done < <(swapon --show=NAME --noheadings 2>/dev/null | awk '{$1=$1;print}' || true)

  # lvm pv
  if command -v pvs >/dev/null 2>&1; then
    while IFS= read -r pv; do
      [[ -n "$pv" ]] || continue
      if [[ "$pv" == "$disk"* ]]; then
        DISK_HAS_LVM=1
        DISK_NEEDS_RELEASE=1
        break
      fi
    done < <(pvs --noheadings -o pv_name 2>/dev/null | awk '{$1=$1;print}' || true)
  fi

  # md
  if [[ -r /proc/mdstat ]]; then
    local base
    base="$(basename "$disk")"
    if grep -q "$base" /proc/mdstat; then
      DISK_HAS_MD=1
      DISK_NEEDS_RELEASE=1
    fi
  fi
}
