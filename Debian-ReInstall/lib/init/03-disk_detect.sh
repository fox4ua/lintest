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
  DISK_DETECT_INCOMPLETE=0
  local parts
  if command -v lsblk >/dev/null 2>&1; then
    parts="$(lsblk -ln -o PATH "$disk" 2>/dev/null | tail -n +2 || true)"
  else
    DISK_DETECT_INCOMPLETE=1
    log "[!] disk detect: lsblk not found, disk usage check incomplete"
    echo "Warning: lsblk not found, disk usage check incomplete." >&2
    parts=""
  fi
  # mounts
  if command -v findmnt >/dev/null 2>&1; then
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
  else
    DISK_DETECT_INCOMPLETE=1
    log "[!] disk detect: findmnt not found, mount check skipped"
    echo "Warning: findmnt not found, mount check skipped." >&2
  fi

  # swap
  if command -v swapon >/dev/null 2>&1; then
    while IFS= read -r s; do
      [[ -n "$s" ]] || continue
      if [[ "$s" == "$disk"* ]]; then
        DISK_HAS_SWAP=1
        DISK_NEEDS_RELEASE=1
        break
      fi
    done < <(swapon --show=NAME --noheadings 2>/dev/null | awk '{$1=$1;print}' || true)
  else
    DISK_DETECT_INCOMPLETE=1
    log "[!] disk detect: swapon not found, swap check skipped"
    echo "Warning: swapon not found, swap check skipped." >&2
  fi

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
  else
    DISK_DETECT_INCOMPLETE=1
    log "[!] disk detect: pvs not found, LVM check skipped"
    echo "Warning: pvs not found, LVM check skipped." >&2
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
