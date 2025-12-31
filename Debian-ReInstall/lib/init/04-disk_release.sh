#!/usr/bin/env bash

DISK_BUSY_SUMMARY=""
DISK_BUSY_DETAILS=""

disk_collect_busy_info() {
  local disk="$1"
  DISK_BUSY_SUMMARY=""
  DISK_BUSY_DETAILS=""

  [[ -b "$disk" ]] || return 1

  local parts mnts="" swaps="" lvm="" md=""
  parts="$(lsblk -ln -o PATH "$disk" 2>/dev/null | tail -n +2 || true)"

  if [[ -n "$parts" ]]; then
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      local targets
      targets="$(findmnt -nr -S "$p" -o TARGET 2>/dev/null || true)"
      if [[ -n "$targets" ]]; then
        while IFS= read -r t; do
          [[ -n "$t" ]] || continue
          mnts+="$p -> $t"$'\n'
        done <<<"$targets"
      fi
    done <<<"$parts"
  fi

  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    [[ "$s" == "$disk"* ]] && swaps+="$s"$'\n'
  done < <(swapon --show=NAME --noheadings 2>/dev/null | awk '{$1=$1;print}' || true)

  if command -v pvs >/dev/null 2>&1; then
    while IFS= read -r pv; do
      [[ -n "$pv" ]] || continue
      [[ "$pv" == "$disk"* ]] && lvm+="$pv"$'\n'
    done < <(pvs --noheadings -o pv_name 2>/dev/null | awk '{$1=$1;print}' || true)
  fi

  # mdraid presence on this disk (best-effort)
  if [[ -r /proc/mdstat ]]; then
    local base
    base="$(basename "$disk")"
    if grep -qE "\b${base}[0-9]*\b" /proc/mdstat; then
      md="mdraid: possible arrays reference ${base}"
    fi
  fi

  if [[ -n "$mnts" || -n "$swaps" || -n "$lvm" || -n "$md" ]]; then
    DISK_BUSY_SUMMARY="Диск используется"
    [[ -n "$mnts" ]] && DISK_BUSY_DETAILS+="Смонтированные разделы:\n$mnts\n"
    [[ -n "$swaps" ]] && DISK_BUSY_DETAILS+="Активный swap:\n$swaps\n"
    [[ -n "$lvm" ]] && DISK_BUSY_DETAILS+="LVM PV на диске:\n$lvm\n"
    [[ -n "$md" ]] && DISK_BUSY_DETAILS+="RAID:\n$md\n"
    return 0
  fi

  return 1
}

disk_release_locks() {
  local disk="$1"
  [[ -b "$disk" ]] || return 1

  local parts
  parts="$(lsblk -ln -o PATH "$disk" 2>/dev/null | tail -n +2 || true)"

  # 1) umount all from disk partitions
  if [[ -n "$parts" ]]; then
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      while findmnt -nr -S "$p" >/dev/null 2>&1; do
        local mp
        mp="$(findmnt -nr -S "$p" -o TARGET | head -n1)"
        umount "$mp" || return 1
      done
    done <<<"$parts"
  fi

  # 2) swapoff for swaps on disk
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    if [[ "$s" == "$disk"* ]]; then
      swapoff "$s" >/dev/null 2>&1 || return 1
    fi
  done < <(swapon --show=NAME --noheadings 2>/dev/null | awk '{$1=$1;print}' || true)

  # 3) Deactivate all VGs (simple & safe in rescue)
  if command -v vgchange >/dev/null 2>&1; then
    vgchange -an >/dev/null 2>&1 || true
  fi

  # 4) Stop md arrays (best-effort)
  if command -v mdadm >/dev/null 2>&1; then
    # stop listed md devices
    while IFS= read -r mddev; do
      [[ -n "$mddev" ]] || continue
      mdadm --stop "$mddev" >/dev/null 2>&1 || true
    done < <(ls /dev/md* 2>/dev/null | grep -E '/dev/md[0-9]+' || true)
  fi

  # 5) dmsetup remove all (best-effort)
  if command -v dmsetup >/dev/null 2>&1; then
    dmsetup remove_all >/dev/null 2>&1 || true
  fi

  # 6) drop kpartx mappings
  if command -v kpartx >/dev/null 2>&1; then
    kpartx -d "$disk" >/dev/null 2>&1 || true
  fi

  return 0
}
