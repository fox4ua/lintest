#!/usr/bin/env bash
# shellcheck shell=bash

# Release disk:
# - swapoff (including swap on /dev/mapper)
# - umount mounts whose SOURCE depends on $disk (including /dev/mapper, dm-*)
# - vgchange -an for VGs that have PVs on this disk
# - dmsetup remove leftovers that depend on this disk

exec_release_disk() {
  local disk="$1"

  if [[ -z "$disk" || ! -b "$disk" ]]; then
    log "[!] disk_release: invalid disk: $disk"
    return 1
  fi

  if disk_is_current_env_disk "$disk"; then
    log "[!] disk_release: refusing to operate on current environment disk: $disk"
    ui_msg "Refusing to operate on current environment disk: ${disk}"
    return 1
  fi

  exec_require_tools findmnt lsblk umount swapon swapoff vgchange pvs dmsetup udevadm || return 1

  log "[=] disk_release: begin disk=$disk"

  # 1) swapoff that depends on disk (including /dev/mapper)
  exec_release_swap_deps "$disk"

  # 2) unmount everything that depends on disk (including /dev/mapper, dm-*)
  exec_release_mounts_deps "$disk"

  # 3) deactivate VGs which have PVs on this disk
  exec_release_lvm_vgs_on_disk "$disk"

  # 4) remove leftover dm devices that still depend on disk (best-effort)
  exec_release_dm_on_disk "$disk"

  # settle udev
  exec_try udevadm settle

  log "[=] disk_release: done disk=$disk"
  return 0
}

# ---------- dependency checks ----------

# Return 0 if $dev ultimately depends on $disk (via PKNAME chain)
exec_dev_depends_on_disk() {
  local dev="$1"
  local disk="$2"

  [[ -n "$dev" && -n "$disk" ]] || return 1
  [[ -b "$disk" ]] || return 1

  local base
  base="$(basename "$disk")"

  # normalize device path (e.g. /dev/mapper/xxx -> /dev/dm-0)
  dev="$(readlink -f "$dev" 2>/dev/null || echo "$dev")"
  [[ -b "$dev" ]] || return 1

  local pk
  while :; do
    # Any direct match: sdb / sdb4 / sdb1...
    local n
    n="$(basename "$dev")"
    [[ "$n" == "$base"* ]] && return 0

    pk="$(lsblk -no PKNAME "$dev" 2>/dev/null | head -n1 || true)"
    [[ -n "$pk" ]] || return 1
    dev="/dev/$pk"
  done
}

# ---------- swapoff ----------

exec_release_swap_deps() {
  local disk="$1"
  local s

  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    # swapon lists devices and/or files; only handle block devices
    if [[ -b "$s" ]] && exec_dev_depends_on_disk "$s" "$disk"; then
      exec_try swapoff "$s"
    fi
  done < <(swapon --show=NAME --noheadings 2>/dev/null | awk '{$1=$1;print}' || true)
}

# ---------- umount mounts depending on disk ----------

exec_release_mounts_deps() {
  local disk="$1"

  local -a lines=()
  local src tgt

  # Collect mounts whose SOURCE depends on disk OR mountpoint is under TARGET_DIR (if set)
  while IFS= read -r src tgt; do
    [[ -n "$src" && -n "$tgt" ]] || continue

    # skip root mountpoint safety (never unmount /)
    [[ "$tgt" == "/" ]] && continue

    local match=0

    if [[ -b "$src" ]] && exec_dev_depends_on_disk "$src" "$disk"; then
      match=1
    fi

    if [[ -n "${TARGET_DIR:-}" ]] && [[ "$tgt" == "${TARGET_DIR}" || "$tgt" == "${TARGET_DIR}/"* ]]; then
      # if installer target tree is mounted, it MUST be released on reruns
      match=1
    fi

    if (( match )); then
      # store: "len target|target"
      lines+=("$(printf '%04d' "${#tgt}")|$tgt")
    fi
  done < <(findmnt -rn -o SOURCE,TARGET 2>/dev/null | awk '{$1=$1;print}')

  # Unmount deepest paths first
  if [[ ${#lines[@]} -gt 0 ]]; then
    printf '%s\n' "${lines[@]}" | sort -r | while IFS='|' read -r _len mp; do
      [[ -n "$mp" ]] || continue
      log "[>] umount ${mp}"
      if umount "$mp"; then
        :
      else
        log "[!] umount failed, trying lazy: ${mp}"
        umount -l "$mp" || log "[!] lazy umount failed: ${mp}"
      fi
    done
  fi
}

# ---------- LVM deactivate ----------

exec_release_lvm_vgs_on_disk() {
  local disk="$1"

  # VGs that have PVs on this disk:
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
}

# ---------- dm cleanup ----------

exec_release_dm_on_disk() {
  local disk="$1"
  local base
  base="$(basename "$disk")"

  # Remove dm devices whose deps include this disk partitions (best-effort)
  local name deps
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    deps="$(dmsetup deps -o devname "$name" 2>/dev/null || true)"
    if grep -qE "(${base}[0-9]+|${base})" <<<"$deps"; then
      log "[>] dmsetup remove -f ${name} (deps: ${deps//$'\n'/ })"
      dmsetup remove -f "$name" >/dev/null 2>&1 || log "[!] dmsetup remove failed: ${name}"
    fi
  done < <(dmsetup ls --noheadings -o name 2>/dev/null || true)
}
