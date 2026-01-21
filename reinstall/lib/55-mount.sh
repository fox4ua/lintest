#!/usr/bin/env bash
# shellcheck shell=bash

# Mount helpers: mount target filesystem tree, chroot bind-mounts, cleanup.
#
# Inputs (globals):
#   TARGET, BOOT_MODE
#   ROOT_DEV, DATA_DEV
#   P_BOOT, P1
#   HAS_SWAP, SWAP_DEV
#
# Requires:
#   log() (lib/00-log.sh)

mount_cleanup_target_if_mounted() {
  local target="${1:-$TARGET}"
  log "Unmounting ${target} if mounted..."
  if mountpoint -q "${target}"; then
    umount -R "${target}" || true
  fi
}

mount_target_tree() {
  log "Mounting target to ${TARGET}..."
  mkdir -p "${TARGET}"
  mount "${ROOT_DEV}" "${TARGET}"

  mkdir -p "${TARGET}/boot"
  mount "${P_BOOT}" "${TARGET}/boot"

  if [[ "${BOOT_MODE}" == "uefi" ]]; then
    mkdir -p "${TARGET}/boot/efi"
    mount "${P1}" "${TARGET}/boot/efi"
  fi

  mkdir -p "${TARGET}/var/lib/vz"
  mount "${DATA_DEV}" "${TARGET}/var/lib/vz"
}

mount_enable_swap() {
  if [[ "${HAS_SWAP:-0}" == "1" ]]; then
    if [[ -n "${SWAP_DEV:-}" ]]; then
      log "Enabling swap (${SWAP_DEV})..."
      swapon "${SWAP_DEV}" || true
    else
      log "WARN: HAS_SWAP=1 but SWAP_DEV is empty; skipping swapon"
    fi
  fi
}

mount_chroot_binds() {
  log "Preparing chroot mounts..."
  mount --bind /dev "${TARGET}/dev"
  mount --bind /dev/pts "${TARGET}/dev/pts"
  mount -t proc proc "${TARGET}/proc"
  mount -t sysfs sys "${TARGET}/sys"
  mount --bind /run "${TARGET}/run" || true
}

mount_cleanup_all() {
  log "Cleaning up mounts..."
  umount -R "${TARGET}/dev/pts" || true
  umount -R "${TARGET}/dev" || true
  umount -R "${TARGET}/proc" || true
  umount -R "${TARGET}/sys" || true
  umount -R "${TARGET}/run" || true
  umount -R "${TARGET}/boot/efi" || true
  umount -R "${TARGET}/boot" || true
  umount -R "${TARGET}/var/lib/vz" || true
  umount -R "${TARGET}" || true
}

mount_disable_swap() {
  if [[ "${HAS_SWAP:-0}" == "1" ]]; then
    if [[ -n "${SWAP_DEV:-}" ]]; then
      swapoff "${SWAP_DEV}" || true
    else
      log "WARN: HAS_SWAP=1 but SWAP_DEV is empty; skipping swapoff"
    fi
  fi
}
