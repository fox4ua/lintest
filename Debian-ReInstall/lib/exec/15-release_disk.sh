#!/usr/bin/env bash
# shellcheck shell=bash

# Device set for current release operation.
# Filled by disk_release_build_devset().
declare -Ag DISK_RELEASE_DEVSET=()

disk_release_build_devset() {
  local disk="$1"
  DISK_RELEASE_DEVSET=()

  if [[ -z "$disk" || ! -b "$disk" ]]; then
    return 1
  fi

  # Best source of truth: lsblk subtree for the disk.
  # This includes partitions and any mapped devices (dm-*, /dev/mapper/*) currently active.
  if command -v lsblk >/dev/null 2>&1; then
    while IFS= read -r dev; do
      [[ -n "$dev" ]] || continue
      DISK_RELEASE_DEVSET["$dev"]=1
      # also add canonical path to cover /dev/mapper/<vg>-<lv> <-> /dev/dm-N
      local canon
      canon="$(readlink -f "$dev" 2>/dev/null || true)"
      [[ -n "$canon" ]] && DISK_RELEASE_DEVSET["$canon"]=1
    done < <(
      lsblk -rpno NAME "$disk" 2>/dev/null \
        | awk 'NF{print $1}' \
        | sort -u
    )
  else
    DISK_RELEASE_DEVSET["$disk"]=1
  fi

  return 0
}

disk_release_src_on_disk() {
  # Returns 0 if $1 is a real device path that belongs to DISK_RELEASE_DEVSET.
  local src="$1"
  [[ -n "$src" ]] || return 1
  [[ "$src" == /dev/* ]] || return 1

  local canon
  canon="$(readlink -f "$src" 2>/dev/null || echo "$src")"

  [[ -n "${DISK_RELEASE_DEVSET["$src"]:-}" ]] && return 0
  [[ -n "${DISK_RELEASE_DEVSET["$canon"]:-}" ]] && return 0
  return 1
}

disk_release_verify_clean() {
  # Verify that nothing from the disk is still mounted/swapped/active.
  local disk="$1"
  local rc=0
  local base

  base="$(basename "$disk")"

  # mounts
  if command -v findmnt >/dev/null 2>&1; then
    local line src tgt
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      src="$(awk '{print $1}' <<<"$line")"
      tgt="$(awk '{print $2}' <<<"$line")"
      [[ -n "$src" && -n "$tgt" ]] || continue
      disk_release_src_on_disk "$src" || continue
      [[ "$tgt" != "/" ]] || continue
      log "[!] disk_release: still mounted: ${src} -> ${tgt}"
      rc=1
    done < <(findmnt -rn -o SOURCE,TARGET 2>/dev/null || true)
  fi

  # swap
  if command -v swapon >/dev/null 2>&1; then
    local s
    while IFS= read -r s; do
      [[ -n "$s" ]] || continue
      disk_release_src_on_disk "$s" || continue
      log "[!] disk_release: still active swap: ${s}"
      rc=1
    done < <(swapon --show=NAME --noheadings 2>/dev/null | awk '{$1=$1;print}' || true)
  fi

  # lvm (best-effort check)
  if command -v pvs >/dev/null 2>&1 && command -v lvs >/dev/null 2>&1; then
    local vg
    while IFS= read -r vg; do
      [[ -n "$vg" && "$vg" != "-" ]] || continue
      # If any LV in VG is still active -> not clean.
      if env LVM_SUPPRESS_FD_WARNINGS=1 lvs --noheadings --separator '|' -o vg_name,lv_path,lv_active 2>/dev/null \
        | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$1); gsub(/^[ \t]+|[ \t]+$/,"",$2); gsub(/^[ \t]+|[ \t]+$/,"",$3); print $1"|"$2"|"$3}' \
        | awk -F'|' -v want="$vg" '$1==want && $3=="active" {print $2; found=1} END{exit(found?0:1)}'
      then
        log "[!] disk_release: VG ${vg} still has active LV(s)"
        rc=1
      fi
    done < <(
      env LVM_SUPPRESS_FD_WARNINGS=1 pvs --noheadings -o pv_name,vg_name 2>/dev/null \
        | awk '{$1=$1;print}' \
        | awk -v d="$disk" '$1 ~ "^"d {print $2}' \
        | sort -u || true
    )
  fi

  # mdraid
  if [[ -r /proc/mdstat ]]; then
    if grep -q "$base" /proc/mdstat; then
      log "[!] disk_release: disk is still part of mdraid: ${disk}"
      rc=1
    fi
  fi

  return "$rc"
}

exec_release_disk() {
  local disk="$1"
  local rc=0

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
  disk_release_build_devset "$disk" || true

  exec_release_swap "$disk" || rc=1
  exec_release_mounts "$disk" || rc=1
  exec_release_lvm "$disk" || rc=1
  exec_release_md "$disk" || rc=1

  # Final verification: do not claim success if resources are still in use.
  if ! disk_release_verify_clean "$disk"; then
    rc=1
  fi

  if (( rc != 0 )); then
    log "[!] disk_release: FAILED disk=$disk"
    return 1
  fi

  log "[=] disk_release: done disk=$disk"
  return 0
}

exec_release_md() {
  local disk="$1"
  local rc=0
  local base

  [[ -r /proc/mdstat ]] || return 0

  base="$(basename "$disk")"

  local -a arrays=()
  mapfile -t arrays < <(
    awk -v base="$base" '
      /^[[:alnum:]]+ :/ {md=$1}
      md != "" && $0 ~ base {print md}
    ' /proc/mdstat | sort -u
  )

  if (( ${#arrays[@]} == 0 )); then
    return 0
  fi

  if ! command -v mdadm >/dev/null 2>&1; then
    log "[!] disk_release: mdadm not found; cannot stop arrays: ${arrays[*]}"
    ui_msg "Disk is part of an mdraid array (${arrays[*]}).\n\nmdadm is not available, so the array cannot be stopped automatically.\nInstall mdadm or stop the array manually, then retry.\nLog: ${LOG_FILE}"
    return 1
  fi

  local md
  for md in "${arrays[@]}"; do
    log "[>] mdadm --stop /dev/${md}"
    if ! mdadm --stop "/dev/${md}" >/dev/null 2>&1; then
      log "[!] mdadm --stop failed: /dev/${md}"
      rc=1
    fi
  done

  return "$rc"
}

exec_release_swap() {
  local disk="$1"
  local rc=0

  if ! command -v swapon >/dev/null 2>&1; then
    log "[!] disk_release: swapon not found, swap check skipped"
    return 0
  fi

  local s
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    disk_release_src_on_disk "$s" || continue
    log "[>] swapoff ${s}"
    if ! swapoff "$s"; then
      log "[!] swapoff failed: ${s}"
      rc=1
    fi
  done < <(swapon --show=NAME --noheadings 2>/dev/null | awk '{$1=$1;print}' || true)

  return "$rc"
}

exec_release_mounts() {
  local disk="$1"
  local rc=0

  if ! command -v findmnt >/dev/null 2>&1; then
    log "[!] disk_release: findmnt not found, mount check skipped"
    return 0
  fi

  local -a root_mounts=()
  local line src tgt
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    src="$(awk '{print $1}' <<<"$line")"
    tgt="$(awk '{print $2}' <<<"$line")"
    [[ -n "$src" && -n "$tgt" ]] || continue
    [[ "$tgt" != "/" ]] || continue
    disk_release_src_on_disk "$src" || continue
    root_mounts+=("$tgt")
  done < <(findmnt -rn -o SOURCE,TARGET 2>/dev/null || true)

  if (( ${#root_mounts[@]} == 0 )); then
    return 0
  fi

  local uniq_roots
  uniq_roots="$(printf '%s\n' "${root_mounts[@]}" | sort -u)"

  local -a targets=()
  while IFS= read -r tgt; do
    [[ -n "$tgt" ]] || continue
    targets+=("$tgt")
  done < <(
    while IFS= read -r tgt; do
      [[ -n "$tgt" ]] || continue
      findmnt -rn -o TARGET -R "$tgt" 2>/dev/null || true
    done <<<"$uniq_roots" \
      | sort -u \
      | awk '{print length($1), $1}' \
      | sort -rn \
      | awk '{print $2}'
  )

  local target
  for target in "${targets[@]}"; do
    [[ -n "$target" ]] || continue
    [[ "$target" != "/" ]] || continue
    log "[>] umount ${target}"
    if umount "$target"; then
      :
    else
      log "[!] umount failed, trying lazy: ${target}"
      umount -l "$target" || true
    fi

    if findmnt -nr "$target" >/dev/null 2>&1; then
      log "[!] still mounted after umount: ${target}"
      rc=1
    fi
  done

  return "$rc"
}

exec_release_lvm() {
  local disk="$1"
  local rc=0

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
  done < <(
    env LVM_SUPPRESS_FD_WARNINGS=1 pvs --noheadings -o pv_name,vg_name 2>/dev/null \
      | awk '{$1=$1;print}' || true
  )

  if [[ ${#vgs[@]} -eq 0 ]]; then
    return 0
  fi

  local uniq
  uniq="$(printf '%s\n' "${vgs[@]}" | sort -u)"

  while IFS= read -r vg; do
    [[ -n "$vg" ]] || continue

    # Deactivate active LVs first (more informative failures than vgchange).
    if command -v lvs >/dev/null 2>&1 && command -v lvchange >/dev/null 2>&1; then
      while IFS='|' read -r vg2 lvpath lvactive; do
        [[ "$vg2" == "$vg" ]] || continue
        [[ "$lvactive" == "active" ]] || continue
        [[ -n "$lvpath" ]] || continue
        log "[>] lvchange -an ${lvpath}"
        if ! env LVM_SUPPRESS_FD_WARNINGS=1 lvchange -an "$lvpath"; then
          log "[!] lvchange -an failed: ${lvpath}"
          rc=1
        fi
      done < <(
        env LVM_SUPPRESS_FD_WARNINGS=1 lvs --noheadings --separator '|' -o vg_name,lv_path,lv_active 2>/dev/null \
          | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$1); gsub(/^[ \t]+|[ \t]+$/,"",$2); gsub(/^[ \t]+|[ \t]+$/,"",$3); print $1"|"$2"|"$3}' \
          || true
      )
    fi

    log "[>] vgchange -an ${vg}"
    if ! env LVM_SUPPRESS_FD_WARNINGS=1 vgchange -an "$vg"; then
      log "[!] disk_release: vgchange -an ${vg} failed"
      rc=1
    fi

    # Verify no active LVs remain.
    if command -v lvs >/dev/null 2>&1; then
      if env LVM_SUPPRESS_FD_WARNINGS=1 lvs --noheadings --separator '|' -o vg_name,lv_path,lv_active 2>/dev/null \
        | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$1); gsub(/^[ \t]+|[ \t]+$/,"",$2); gsub(/^[ \t]+|[ \t]+$/,"",$3); print $1"|"$2"|"$3}' \
        | awk -F'|' -v want="$vg" '$1==want && $3=="active" {print $2; found=1} END{exit(found?0:1)}'
      then
        log "[!] disk_release: ${vg} still has active LV(s) after deactivate"
        rc=1
      fi
    fi

  done <<<"$uniq"

  return "$rc"
}
