#!/usr/bin/env bash
# shellcheck shell=bash

# Chroot mounts:
#   /dev, /dev/pts, /proc, /sys, /run -> ${TARGET_DIR}
#
# Public:
#   exec_chroot_mounts
#   exec_chroot_umounts
#   exec_in_chroot (helper for next steps)
#
# Requires variables:
#   TARGET_DIR
#   LOG_FILE

exec_chroot_mounts() {
  : "${TARGET_DIR:?TARGET_DIR is required}"
  : "${LOG_FILE:?LOG_FILE is required}"

  exec_require_tools mount umount findmnt chroot mkdir || return 1

  if ! findmnt -rn "${TARGET_DIR}" >/dev/null 2>&1; then
    log "[!] chroot_mounts: TARGET_DIR is not mounted: ${TARGET_DIR}"
    ui_msg "Chroot mounts require mounted TARGET_DIR:\n${TARGET_DIR}\nLog: ${LOG_FILE}"
    return 1
  fi

  exec_progress 0 "Preparing chroot mountpoints..."
  mkdir -p \
    "${TARGET_DIR}/dev" \
    "${TARGET_DIR}/dev/pts" \
    "${TARGET_DIR}/proc" \
    "${TARGET_DIR}/sys" \
    "${TARGET_DIR}/run" || true

  exec_progress 15 "Mounting /dev..."
  exec_mount_bind_if_needed "/dev" "${TARGET_DIR}/dev" || return 1

  exec_progress 30 "Mounting /dev/pts..."
  exec_mount_bind_if_needed "/dev/pts" "${TARGET_DIR}/dev/pts" || return 1

  exec_progress 50 "Mounting /proc..."
  exec_mount_fs_if_needed "proc" "proc" "${TARGET_DIR}/proc" || return 1

  exec_progress 70 "Mounting /sys..."
  exec_mount_fs_if_needed "sysfs" "sys" "${TARGET_DIR}/sys" || return 1

  exec_progress 85 "Mounting /run..."
  exec_mount_bind_if_needed "/run" "${TARGET_DIR}/run" || return 1

  exec_progress 95 "Verifying chroot mounts..."
  exec_try findmnt -rn "${TARGET_DIR}/dev" || true
  exec_try findmnt -rn "${TARGET_DIR}/dev/pts" || true
  exec_try findmnt -rn "${TARGET_DIR}/proc" || true
  exec_try findmnt -rn "${TARGET_DIR}/sys" || true
  exec_try findmnt -rn "${TARGET_DIR}/run" || true

  exec_progress 100 "Chroot mounts done."
  log "[=] chroot_mounts: OK target=${TARGET_DIR}"
  return 0
}

exec_chroot_umounts() {
  : "${TARGET_DIR:?TARGET_DIR is required}"

  exec_require_tools umount findmnt || return 1

  exec_progress 0 "Unmounting chroot mounts..."

  exec_umount_if_mounted "${TARGET_DIR}/run"
  exec_umount_if_mounted "${TARGET_DIR}/sys"
  exec_umount_if_mounted "${TARGET_DIR}/proc"
  exec_umount_if_mounted "${TARGET_DIR}/dev/pts"
  exec_umount_if_mounted "${TARGET_DIR}/dev"

  exec_progress 100 "Chroot umounts done."
  return 0
}

exec_mount_bind_if_needed() {
  local src="$1" dst="$2"

  if findmnt -rn "$dst" >/dev/null 2>&1; then
    log "[=] chroot_mounts: ${dst} already mounted"
    return 0
  fi

  exec_run mount --bind "$src" "$dst" || return 1
  mount --make-rslave "$dst" >/dev/null 2>&1 || true
  return 0
}

exec_mount_fs_if_needed() {
  local fstype="$1" src="$2" dst="$3"

  if findmnt -rn "$dst" >/dev/null 2>&1; then
    log "[=] chroot_mounts: ${dst} already mounted"
    return 0
  fi

  exec_run mount -t "$fstype" "$src" "$dst" || return 1
  mount --make-rslave "$dst" >/dev/null 2>&1 || true
  return 0
}

exec_umount_if_mounted() {
  local mp="$1"

  if findmnt -rn "$mp" >/dev/null 2>&1; then
    exec_try umount "$mp"
    if findmnt -rn "$mp" >/dev/null 2>&1; then
      exec_try umount -l "$mp"
    fi
  fi

  return 0
}

exec__close_extra_fds() {
  local fd
  if [[ -d /proc/$$/fd ]]; then
    for fd in /proc/$$/fd/*; do
      fd="${fd##*/}"
      if [[ "$fd" =~ ^[0-9]+$ ]] && (( fd > 2 )); then
        eval "exec ${fd}>&-"
      fi
    done
  fi
}

exec_in_chroot() {
  : "${TARGET_DIR:?TARGET_DIR is required}"
  log "[>] chroot: $*"
  (
    exec__close_extra_fds
    chroot "${TARGET_DIR}" /usr/bin/env -i \
      HOME=/root \
      TERM="${TERM:-xterm}" \
      PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
      "$@" >>"${LOG_FILE}" 2>&1
  )
}
