#!/usr/bin/env bash
# shellcheck shell=bash

# lib/exec/04-mkfs.sh
#
# Creates filesystems:
# - EFI (vfat) on PART_EFI (if set)
# - /boot (ext4) on PART_BOOT (if set)
# - swap (mkswap) on PART_SWAP (if set)
# - root (ext4) on ROOT_DEV (LV_ROOT if LVM, else PART_ROOT)
#
# Exports:
#   ROOT_DEV (device to mount as /)
#
# Requires variables:
#   LOG_FILE
#   BOOT_MODE, LVM_MODE
#   PART_EFI, PART_BOOT, PART_SWAP, PART_ROOT
#   LV_ROOT (if LVM_MODE != none)

exec_mkfs_all() {
  : "${LVM_MODE:?}"
  : "${BOOT_MODE:?}"

  exec_require_tools \
    findmnt \
    wipefs \
    blkid \
    mkfs.ext4 \
    mkfs.vfat \
    mkswap || return 1

  local root_dev=""
  if [[ "${LVM_MODE}" == "none" ]]; then
    root_dev="${PART_ROOT:-}"
  else
    root_dev="${LV_ROOT:-}"
  fi

  if [[ -z "$root_dev" ]]; then
    log "[!] mkfs: ROOT device is empty (LVM_MODE=${LVM_MODE} PART_ROOT=${PART_ROOT:-} LV_ROOT=${LV_ROOT:-})"
    ui_msg "mkfs: ROOT device is not defined.\nSee log: ${LOG_FILE}"
    return 1
  fi

  # Wait for devices to exist (especially after LVM creation)
  exec_progress 0 "Waiting for devices..."
  [[ -z "${PART_EFI:-}" ]]  || exec_wait_for_path "${PART_EFI}"  60 || return 1
  [[ -z "${PART_BOOT:-}" ]] || exec_wait_for_path "${PART_BOOT}" 60 || return 1
  [[ -z "${PART_SWAP:-}" ]] || exec_wait_for_path "${PART_SWAP}" 60 || return 1
  exec_wait_for_path "$root_dev" 60 || return 1

  exec_progress 10 "Checking mounts..."
  exec_assert_not_mounted "${PART_EFI:-}"  || return 1
  exec_assert_not_mounted "${PART_BOOT:-}" || return 1
  exec_assert_not_mounted "${PART_SWAP:-}" || return 1
  exec_assert_not_mounted "$root_dev"      || return 1

  # EFI
  if [[ -n "${PART_EFI:-}" ]]; then
    exec_progress 20 "Formatting EFI (vfat)..."
    exec_try wipefs -a "${PART_EFI}"
    exec_run mkfs.vfat -F 32 -n EFI "${PART_EFI}" || return 1
  else
    log "[=] mkfs: EFI skipped (no PART_EFI)"
  fi

  # /boot
  if [[ -n "${PART_BOOT:-}" ]]; then
    exec_progress 40 "Formatting /boot (ext4)..."
    exec_try wipefs -a "${PART_BOOT}"
    exec_run mkfs.ext4 -F -L boot "${PART_BOOT}" || return 1
  else
    log "[=] mkfs: /boot skipped (no PART_BOOT)"
  fi

  # swap
  if [[ -n "${PART_SWAP:-}" ]]; then
    exec_progress 60 "Creating swap..."
    exec_try wipefs -a "${PART_SWAP}"
    exec_run mkswap -L swap "${PART_SWAP}" || return 1
  else
    log "[=] mkfs: swap skipped (no PART_SWAP)"
  fi

  # root
  exec_progress 80 "Formatting root (ext4)..."
  exec_try wipefs -a "${root_dev}"
  exec_run mkfs.ext4 -F -L root "${root_dev}" || return 1

  # Log UUIDs (for future fstab)
  exec_progress 90 "Reading UUIDs..."
  exec_try blkid "${PART_EFI:-}"  || true
  exec_try blkid "${PART_BOOT:-}" || true
  exec_try blkid "${PART_SWAP:-}" || true
  exec_try blkid "${root_dev}"    || true

  ROOT_DEV="$root_dev"
  export ROOT_DEV

  log "[=] mkfs: OK root=${ROOT_DEV} efi=${PART_EFI:-none} boot=${PART_BOOT:-none} swap=${PART_SWAP:-none}"
  exec_progress 100 "Filesystems created."
  return 0
}

exec_assert_not_mounted() {
  local dev="$1"
  [[ -n "$dev" ]] || return 0

  if findmnt -rn -S "$dev" >/dev/null 2>&1; then
    log "[!] mkfs: device is mounted: $dev"
    exec_try findmnt -rn -S "$dev" || true
    ui_msg "Refusing to format mounted device:\n${dev}\n\nSee log: ${LOG_FILE}"
    return 1
  fi

  return 0
}
