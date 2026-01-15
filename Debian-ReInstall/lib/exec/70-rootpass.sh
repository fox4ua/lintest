#!/usr/bin/env bash
# shellcheck shell=bash

# Sets root password inside chroot.
# Requires:
#   TARGET_DIR, LOG_FILE, ROOT_PASS

exec_rootpass_set() {
  : "${TARGET_DIR:?}"
  : "${LOG_FILE:?}"
  : "${ROOT_PASS:?ROOT_PASS is required}"

  exec_require_tools chroot || return 1

  exec_progress 0 "Setting root password..."

  printf 'root:%s\n' "${ROOT_PASS}" \
    | chroot "${TARGET_DIR}" chpasswd >>"${LOG_FILE}" 2>&1 || {
      local rc=$?
      ui_msg "Failed to set root password (rc=${rc}).\nLog: ${LOG_FILE}"
      return 1
    }

  exec_progress 100 "Root password set."
  return 0
}
