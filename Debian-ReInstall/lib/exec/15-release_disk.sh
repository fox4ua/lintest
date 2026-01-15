#!/usr/bin/env bash
# shellcheck shell=bash

exec_release_disk() {
  local disk="$1"

  if [[ -z "$disk" || ! -b "$disk" ]]; then
    log "[!] disk_release: invalid disk: $disk"
    return 1
  fi

  # Safety: never touch the current rescue/live environment disk.
  if disk_is_current_env_disk "$disk"; then
    log "[!] disk_release: refusing to operate on current environment disk: $disk"
    ui_msg "Refusing to operate on current environment disk: ${disk}"
    return 1
  fi

  exec_require_tools lsblk findmnt umount swapon swapoff pvs vgchange dmsetup udevadm || return 1

  log "[=] disk_release: begin disk=$disk"

  exec_release_swap_deps "$disk"
  exec_release_mounts_tree "$disk"
  exec_release_mounts_targetdir
  exec_release_lvm_vgs_on_disk "$disk"
  exec_release_dm_on_disk "$disk"

  exec_try udevadm settle

  log "[=] disk_release: done disk=$disk"
  return 0
}

# dev depends on disk if PKNAME chain reaches disk (works for /dev/mapper/* and /dev/dm-*)
exec_dev_depends_on_disk() {
  local dev="$1"
  local disk="$2"
  local base pk

  [[ -n "$dev" && -n "$disk" ]] || return 1
  [[ -b "$disk" ]] || return 1

  base="$(basename "$disk")"
  dev="$(readlink -f "$dev" 2>/dev/null || echo "$dev")"
  [[ -b "$dev" ]] || return 1

  while :; do
    [[ "$(basename "$dev")" == "$base"* ]] && return 0
    pk="$(lsblk -no PKNAME "$dev" 2>/dev/null | head -n1 || true)"
    [[ -n "$pk" ]] || return 1
    dev="/dev/$pk"
  done
}

exec_release_swap_deps() {
  local disk="$1"
  local s

  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    [[ -b "$s" ]] || continue
    if exec_dev_depends_on_disk "$s" "$disk"; then
      exec_try swapoff "$s"
    fi
  done < <(swapon --show=NAME --noheadings 2>/dev/null | awk '{$1=$1;print}' || true)

  return 0
}

# Unmount everything mounted anywhere in the disk tree (includes LVM /dev/mapper children)
exec_release_mounts_tree() {
  local disk="$1"
  local mp

  # deepest mountpoints first
  while IFS= read -r mp; do
    [[ -n "$mp" && "$mp" != "/" ]] || continue
    log "[>] umount ${mp}"
    if exec_run umount "$mp"; then
      :
    else
      log "[!] umount failed, trying lazy: ${mp}"
      if ! exec_run umount -l "$mp"; then
        log "[!] lazy umount failed: ${mp}"
      fi
    fi
  done < <(
    lsblk -rno MOUNTPOINT "$disk" 2>/dev/null \
      | awk 'NF{print length($0) "|" $0}' \
      | sort -rn \
      | cut -d'|' -f2-
  )

  return 0
}

# Fallback: always release installer target tree if it exists (reruns)
exec_release_mounts_targetdir() {
  [[ -n "${TARGET_DIR:-}" ]] || return 0

  local mp
  while IFS= read -r mp; do
    [[ -n "$mp" && "$mp" != "/" ]] || continue
    log "[>] umount ${mp}"
    umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null || true
  done < <(
    findmnt -rn -o TARGET 2>/dev/null \
      | awk -v t="${TARGET_DIR}" '$0==t || index($0,t"/")==1 {print length($0) "|" $0}' \
      | sort -rn \
      | cut -d'|' -f2-
  )

  return 0
}

exec_release_lvm_vgs_on_disk() {
  local disk="$1"
  local vg

  while IFS= read -r vg; do
    [[ -n "$vg" && "$vg" != "-" ]] || continue
    exec_try vgchange -an "$vg"
  done < <(
    pvs --noheadings -o pv_name,vg_name 2>/dev/null \
      | awk -v d="$disk" '$1 ~ "^"d {print $2}' \
      | awk '{$1=$1;print}' \
      | sort -u
  )

  return 0
}

exec_release_dm_on_disk() {
  local disk="$1"
  local base name deps

  base="$(basename "$disk")"

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    deps="$(dmsetup deps -o devname "$name" 2>/dev/null || true)"
    if grep -qE "(${base}[0-9]+|${base})" <<<"$deps"; then
      log "[>] dmsetup remove -f ${name} (deps: ${deps//$'\n'/ })"
      dmsetup remove -f "$name" >/dev/null 2>&1 || log "[!] dmsetup remove failed: ${name}"
    fi
  done < <(dmsetup ls --noheadings -o name 2>/dev/null || true)

  return 0
}
