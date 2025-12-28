#!/usr/bin/env bash
set -Eeuo pipefail

disk_part_prefix() {
  local d="$1"
  if [[ "$d" =~ nvme[0-9]+n[0-9]+$ ]]; then echo "${d}p"; else echo "$d"; fi
}

disk_wait_partitions() {
  local disk="$1"
  local pref; pref="$(disk_part_prefix "$disk")"
  for _ in {1..50}; do
    [[ -b "${pref}1" && -b "${pref}2" && -b "${pref}3" && -b "${pref}4" ]] && return 0
    udevadm settle 2>/dev/null || true
    sleep 0.2
  done
  return 1
}

reload_partitions() {
  local disk="$1"
  sync || true
  udevadm settle 2>/dev/null || true
  partprobe "$disk" 2>/dev/null || true
  blockdev --rereadpt "$disk" 2>/dev/null || true
  udevadm settle 2>/dev/null || true
}

disk_stop_automount_best_effort() {
  systemctl stop udisks2 2>/dev/null || true
  systemctl stop udevil  2>/dev/null || true
}

force_release_disk() {
  local disk="$1"
  local pref; pref="$(disk_part_prefix "$disk")"

  log "Releasing locks for $disk (busy/automount mitigation)"
  disk_stop_automount_best_effort

  while read -r src tgt _; do
    [[ "$src" == ${pref}* ]] || continue
    warn "Unmounting $tgt ($src)"
    umount -lf "$tgt" 2>/dev/null || true
  done < <(findmnt -rn -o SOURCE,TARGET,FSTYPE 2>/dev/null || true)

  while read -r swdev _; do
    [[ "$swdev" == ${pref}* ]] || continue
    warn "Swapoff $swdev"
    swapoff "$swdev" 2>/dev/null || true
  done < <(swapon --noheadings --show=NAME,TYPE 2>/dev/null || true)

  if command -v pvs >/dev/null 2>&1; then
    if pvs --noheadings -o pv_name 2>/dev/null | awk '{print $1}' | grep -qE "^${pref}"; then
      warn "Deactivating all VGs"
      vgchange -an 2>/dev/null || true
      pvscan --cache 2>/dev/null || true
    fi
  fi

  dmsetup remove_all 2>/dev/null || true
  kpartx -d "$disk" 2>/dev/null || true

  reload_partitions "$disk"
}

release_partition() {
  local part="$1"

  while read -r tgt; do
    warn "Unmounting $part from $tgt"
    umount -lf "$tgt" 2>/dev/null || true
  done < <(findmnt -rn -S "$part" -o TARGET 2>/dev/null || true)

  if swapon --noheadings --show=NAME 2>/dev/null | awk '{print $1}' | grep -qx "$part"; then
    warn "Swapoff $part"
    swapoff "$part" 2>/dev/null || true
  fi
}

assert_not_busy() {
  local dev="$1"

  if findmnt -rn -S "$dev" >/dev/null 2>&1; then
    warn "Mounted: $dev"
    findmnt -rn -S "$dev" | tee -a "$LOG_FILE" || true
    die "$dev is mounted; cannot proceed."
  fi

  if command -v fuser >/dev/null 2>&1; then
    if fuser -m "$dev" >/dev/null 2>&1; then
      warn "Busy: $dev (fuser reports users)"
      fuser -mv "$dev" 2>/dev/null | tee -a "$LOG_FILE" || true
      die "$dev is busy; cannot proceed."
    fi
  fi
}

disk_unmount_any_from_disk() {
  local disk="$1"
  local pref; pref="$(disk_part_prefix "$disk")"

  # Если rescue что-то авто-смонтировал — снять
  while read -r src tgt; do
    [[ "$src" == ${pref}* ]] || continue
    warn "Auto-mount detected: unmounting $tgt ($src)"
    umount -lf "$tgt" 2>/dev/null || true
  done < <(findmnt -rn -o SOURCE,TARGET 2>/dev/null || true)

  # Если авто-включили swap — снять
  while read -r swdev; do
    [[ "$swdev" == ${pref}* ]] || continue
    warn "Auto-swap detected: swapoff $swdev"
    swapoff "$swdev" 2>/dev/null || true
  done < <(swapon --noheadings --show=NAME 2>/dev/null || true)

  udevadm settle 2>/dev/null || true
}

disk_fail_if_mounted_from_disk() {
  local disk="$1"
  local pref; pref="$(disk_part_prefix "$disk")"

  if findmnt -rn -o SOURCE,TARGET | awk -v p="^"${pref} '$1 ~ p {print}' | grep -q .; then
    warn "Still mounted from ${disk}:"
    findmnt -rn -o SOURCE,TARGET | awk -v p="^"${pref} '$1 ~ p {print}' | tee -a "$LOG_FILE" || true
    die "Target disk partitions are mounted (automount). Unmount/reboot rescue and retry."
  fi
}

disk_prepare_and_partition() {
  local disk="$1" boot_mode="$2" boot_mib="$3" swap_gb="$4"

  local BIOS_GRUB_START=1 BIOS_GRUB_END=3
  local ESP_START=1 ESP_END=513

  local BOOT_START BOOT_END SWAP_END
  if [[ "$boot_mode" == "bios" ]]; then
    BOOT_START="$BIOS_GRUB_END"
  else
    BOOT_START="$ESP_END"
  fi
  BOOT_END=$(( BOOT_START + boot_mib ))
  SWAP_END=$(( BOOT_END + swap_gb*1024 ))

  log "Wiping signatures on $disk"
  force_release_disk "$disk"

  run wipefs -a "$disk" || true
  run sgdisk --zap-all "$disk"
  reload_partitions "$disk"

  log "Creating GPT partitions (boot_mode=$boot_mode)"
  if [[ "$boot_mode" == "bios" ]]; then
    run parted "$disk" --script \
      mklabel gpt \
      mkpart primary "${BIOS_GRUB_START}MiB" "${BIOS_GRUB_END}MiB" \
      set 1 bios_grub on \
      mkpart primary ext4 "${BOOT_START}MiB" "${BOOT_END}MiB" \
      mkpart primary linux-swap "${BOOT_END}MiB" "${SWAP_END}MiB" \
      mkpart primary "${SWAP_END}MiB" 100%
  else
    run parted "$disk" --script \
      mklabel gpt \
      mkpart primary fat32 "${ESP_START}MiB" "${ESP_END}MiB" \
      set 1 esp on \
      mkpart primary ext4 "${BOOT_START}MiB" "${BOOT_END}MiB" \
      mkpart primary linux-swap "${BOOT_END}MiB" "${SWAP_END}MiB" \
      mkpart primary "${SWAP_END}MiB" 100%
  fi

  reload_partitions "$disk"

  if ! disk_wait_partitions "$disk"; then
    warn "Partition devices not appeared yet. Forcing release + reread..."
    force_release_disk "$disk"
    reload_partitions "$disk"
    disk_wait_partitions "$disk" || die "Kernel did not create partition devices. Reboot rescue and retry."
  fi

  # 🔥 Ключевое: после разметки rescue может авто-смонтировать / включить swap
  disk_unmount_any_from_disk "$disk"
  disk_fail_if_mounted_from_disk "$disk"

  force_release_disk "$disk"
  reload_partitions "$disk"
}

disk_resolve_partitions() {
  local disk="$1" _boot_mode="$2"
  local pref; pref="$(disk_part_prefix "$disk")"
  P1="${pref}1"; P2="${pref}2"; P3="${pref}3"; P4="${pref}4"
  [[ -b "$P1" && -b "$P2" && -b "$P3" && -b "$P4" ]] || die "Partition devices not found: $P1 $P2 $P3 $P4"
}

disk_format_partitions() {
  local boot_mode="$1" p1="$2" p2="$3" p3="$4"

  # 🔥 ещё раз на всякий случай — часто помогает против udisks/auto-mount
  [[ -n "${DISK:-}" ]] && disk_unmount_any_from_disk "$DISK"
  [[ -n "${DISK:-}" ]] && disk_fail_if_mounted_from_disk "$DISK"

  release_partition "$p1" || true
  release_partition "$p2" || true
  release_partition "$p3" || true

  assert_not_busy "$p2"
  assert_not_busy "$p3"

  if [[ "$boot_mode" == "uefi" ]]; then
    assert_not_busy "$p1"
    log "Formatting ESP (vfat)"
    run mkfs.vfat -F 32 "$p1"
  fi

  log "Formatting /boot (ext4)"
  run mkfs.ext4 -F "$p2"

  log "Formatting swap"
  run mkswap "$p3"
}

disk_create_lvm() {
  local p4="$1" root_gb="$2" lvm_mode="$3"

  release_partition "$p4" || true
  assert_not_busy "$p4"

  log "Creating LVM (VG=pve)"
  run wipefs -a "$p4" || true

  run pvcreate -ff -y "$p4"
  run vgcreate -y pve "$p4"

  log "Creating LV root (${root_gb}G)"
  run lvcreate -y -L "${root_gb}G" -n root pve
  run mkfs.ext4 -F /dev/pve/root

  if [[ "$lvm_mode" == "thin" ]]; then
    log "Creating thin-pool data (100%FREE)"
    run lvcreate -y -l 100%FREE -n data pve
    run lvconvert -y --type thin-pool pve/data
  else
    log "Creating linear LV data (100%FREE)"
    run lvcreate -y -l 100%FREE -n data pve
  fi
}

disk_mount_target() {
  local boot_mode="$1" p1="$2" p2="$3" p3="$4"

  run mount /dev/pve/root /mnt
  run mkdir -p /mnt/boot
  run mount "$p2" /mnt/boot

  if [[ "$boot_mode" == "uefi" ]]; then
    run mkdir -p /mnt/boot/efi
    run mount "$p1" /mnt/boot/efi
  fi

  run swapon "$p3"
}

