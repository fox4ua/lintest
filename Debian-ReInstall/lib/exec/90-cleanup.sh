#!/usr/bin/env bash

exec_cleanup() {
  stage "cleanup"

  # Unmount bind mounts and target fs
  umount_chroot_helpers || true

  # Unmount target partitions
  if mountpoint -q "$TARGET_DIR/boot/efi" 2>/dev/null; then
    run_quiet umount "$TARGET_DIR/boot/efi" || true
  fi
  if mountpoint -q "$TARGET_DIR/boot" 2>/dev/null; then
    run_quiet umount "$TARGET_DIR/boot" || true
  fi
  if mountpoint -q "$TARGET_DIR" 2>/dev/null; then
    run_quiet umount "$TARGET_DIR" || true
  fi

  # Deactivate VG used by install
  if [[ "$LVM_MODE" != "none" ]] && command -v vgchange >/dev/null 2>&1; then
    run_quiet vgchange -an "$VG_NAME" || true
  fi
}
