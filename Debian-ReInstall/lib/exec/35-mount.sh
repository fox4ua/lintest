#!/usr/bin/env bash
# shellcheck shell=bash

# Mounts target filesystem tree into TARGET_DIR:
#   ROOT_DEV  -> ${TARGET_DIR}
#   PART_BOOT -> ${TARGET_DIR}/boot    (if set)
#   PART_EFI  -> ${TARGET_DIR}/boot/efi (if set)
#
# Also optionally enables swap (PART_SWAP) depending on SWAP_ENABLE_ON_INSTALL.
#
# Requires variables:
#   TARGET_DIR (e.g. /mnt/target)
#   ROOT_DEV   (from mkfs step)
#   PART_BOOT, PART_EFI, PART_SWAP (optional)
#   LOG_FILE
#
# Exports:
#   TARGET_DIR (unchanged)

: "${SWAP_ENABLE_ON_INSTALL:=0}"   # 1 = swapon during install, 0 = leave off

exec_mount_target() {
  : "${TARGET_DIR:?TARGET_DIR is required}"
  : "${ROOT_DEV:?ROOT_DEV is required}"

  exec_require_tools mount umount findmnt mkdir || return 1

  exec_progress 0 "Preparing mountpoints..."

  # Safety: prevent mounting over unexpected existing mounts
  if findmnt -rn "${TARGET_DIR}" >/dev/null 2>&1; then
    log "[!] mount: TARGET_DIR already mounted: ${TARGET_DIR}"
    exec_try findmnt -rn "${TARGET_DIR}" || true
    ui_msg "TARGET_DIR is already mounted:\n${TARGET_DIR}\n\nRefusing.\nLog: ${LOG_FILE}"
    return 1
  fi

  mkdir -p "${TARGET_DIR}"

  exec_progress 20 "Mounting root..."
  exec_run mount "${ROOT_DEV}" "${TARGET_DIR}" || return 1

  # /boot
  if [[ -n "${PART_BOOT:-}" ]]; then
    exec_progress 45 "Mounting /boot..."
    mkdir -p "${TARGET_DIR}/boot"
    exec_run mount "${PART_BOOT}" "${TARGET_DIR}/boot" || return 1
  else
    log "[=] mount: /boot skipped (no PART_BOOT)"
  fi

  # EFI
  if [[ -n "${PART_EFI:-}" ]]; then
    exec_progress 65 "Mounting EFI..."
    mkdir -p "${TARGET_DIR}/boot/efi"
    exec_run mount "${PART_EFI}" "${TARGET_DIR}/boot/efi" || return 1
  else
    log "[=] mount: EFI skipped (no PART_EFI)"
  fi

  # Create base dirs (best-effort)
  exec_progress 80 "Creating base directories..."
  mkdir -p "${TARGET_DIR}/etc" "${TARGET_DIR}/root" "${TARGET_DIR}/var" "${TARGET_DIR}/usr" || true

  # Optionally enable swap during install
  if [[ -n "${PART_SWAP:-}" ]] && (( SWAP_ENABLE_ON_INSTALL == 1 )); then
    exec_progress 90 "Enabling swap..."
    exec_try swapon "${PART_SWAP}"
  fi

  exec_progress 95 "Verifying mounts..."
  exec_try findmnt -rn "${TARGET_DIR}" || true
  exec_try findmnt -rn "${TARGET_DIR}/boot" || true
  exec_try findmnt -rn "${TARGET_DIR}/boot/efi" || true

  exec_progress 100 "Mount step done."
  log "[=] mount: OK root=${ROOT_DEV} target=${TARGET_DIR}"
  return 0
}

exec_umount_target() {
  : "${TARGET_DIR:?TARGET_DIR is required}"

  exec_require_tools umount findmnt || return 1

  exec_progress 0 "Unmounting target..."

  # Unmount in reverse order if mounted
  if findmnt -rn "${TARGET_DIR}/boot/efi" >/dev/null 2>&1; then
    exec_try umount "${TARGET_DIR}/boot/efi"
  fi
  if findmnt -rn "${TARGET_DIR}/boot" >/dev/null 2>&1; then
    exec_try umount "${TARGET_DIR}/boot"
  fi
  if findmnt -rn "${TARGET_DIR}" >/dev/null 2>&1; then
    exec_try umount "${TARGET_DIR}"
  fi

  exec_progress 100 "Unmount done."
  return 0
}
