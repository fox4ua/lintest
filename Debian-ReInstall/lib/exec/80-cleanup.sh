#!/usr/bin/env bash
# shellcheck shell=bash

# - apt-get clean (best-effort)
# - unmount chroot mounts + target mounts (best-effort)
#
# Depends:
#  exec_in_chroot()
#  exec_chroot_mounts_down() from 07-chroot_mounts.sh
#  exec_umount_target() from 05-mount.sh (if present)

exec_cleanup_all() {
  : "${TARGET_DIR:?}"
  : "${LOG_FILE:?}"

  exec_progress 0 "Cleaning APT (best-effort)..."
  exec_try exec_in_chroot apt-get clean

  exec_progress 40 "Unmounting chroot mounts (best-effort)..."
  if declare -F exec_chroot_mounts_down >/dev/null 2>&1; then
    exec_try exec_chroot_mounts_down
  fi

  exec_progress 70 "Unmounting target (best-effort)..."
  if declare -F exec_umount_target >/dev/null 2>&1; then
    exec_try exec_umount_target
  else
    exec_try umount "${TARGET_DIR}/boot/efi"
    exec_try umount "${TARGET_DIR}/boot"
    exec_try umount "${TARGET_DIR}"
  fi

  exec_progress 100 "Cleanup done."
  return 0
}
