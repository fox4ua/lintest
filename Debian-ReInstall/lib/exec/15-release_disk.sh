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

  log "[=] disk_release: begin disk=$disk"

  exec_release_swap "$disk"
  exec_release_mounts "$disk"
  exec_release_lvm "$disk"

  log "[=] disk_release: done disk=$disk"
}

exec_release_swap() {
  local disk="$1"

  if ! command -v swapon >/dev/null 2>&1; then
    log "[!] disk_release: swapon not found, swap check skipped"
    return 0
  fi

  local s
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    [[ "$s" == "$disk"* ]] || continue
    exec_try swapoff "$s"
  done < <(swapon --show=NAME --noheadings 2>/dev/null | awk '{$1=$1;print}' || true)
}

exec_release_mounts() {
  local disk="$1"

  if ! command -v findmnt >/dev/null 2>&1; then
    log "[!] disk_release: findmnt not found, mount check skipped"
    return 0
  fi

  # Unmount in reverse order (deepest paths first).
  local line src tgt
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    src="$(awk '{print $1}' <<<"$line")"
    tgt="$(awk '{print $2}' <<<"$line")"
    [[ -n "$src" && -n "$tgt" ]] || continue
    [[ "$src" == "$disk"* ]] || continue
    [[ "$tgt" != "/" ]] || continue
    # Try normal umount; if it fails and mount still present, fallback to lazy.
    log "[>] umount ${tgt}"
    if umount "$tgt"; then
      :
    else
      log "[!] umount failed, trying lazy: ${tgt}"
      umount -l "$tgt" || log "[!] lazy umount failed: ${tgt}"
    fi
  done < <(
    findmnt -rn -S "${disk}*" -o SOURCE,TARGET 2>/dev/null \
      | awk '{print length($2), $0}' \
      | sort -rn \
      | cut -d' ' -f2- \
      || true
  )
}

exec_release_lvm() {
  local disk="$1"

  if ! command -v pvs >/dev/null 2>&1; then
    log "[!] disk_release: pvs not found, LVM check skipped"
    return 0
  fi
  if ! command -v vgchange >/dev/null 2>&1; then
    log "[!] disk_release: vgchange not found, LVM deactivate skipped"
    return 0
  fi

  local -a vgs=()
  local line pv vg
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    pv="$(awk '{print $1}' <<<"$line")"
    vg="$(awk '{print $2}' <<<"$line")"
    [[ -n "$pv" ]] || continue
    [[ "$pv" == "$disk"* ]] || continue
    [[ -n "$vg" && "$vg" != "-" ]] || continue
    vgs+=("$vg")
  done < <(pvs --noheadings -o pv_name,vg_name 2>/dev/null | awk '{$1=$1;print}' || true)

  if [[ ${#vgs[@]} -eq 0 ]]; then
    return 0
  fi

  # Unique list.
  local uniq
  uniq="$(printf '%s\n' "${vgs[@]}" | sort -u)"
  while IFS= read -r vg; do
    [[ -n "$vg" ]] || continue
    exec_try vgchange -an "$vg"
  done <<<"$uniq"
}
