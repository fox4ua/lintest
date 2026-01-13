#!/usr/bin/env bash
# shellcheck shell=bash

: "${EXEC_DIR:?}"

# exec core
source "$EXEC_DIR/00-common.sh"
source "$EXEC_DIR/10-runner.sh"

# exec steps (подключай по мере реализации)
source "$EXEC_DIR/20-release_disk.sh"
# source "$EXEC_DIR/02-partition.sh"
# source "$EXEC_DIR/03-mkfs.sh"
# source "$EXEC_DIR/04-mount.sh"
# source "$EXEC_DIR/05-debootstrap.sh"
# source "$EXEC_DIR/06-chroot.sh"

# ---- step wrappers for runner ----

exec_release_disk_step() {
  # этот step должен быть безопасным, если не нужен
  if (( DISK_NEEDS_RELEASE )) && (( DISK_RELEASE_APPROVED )); then
    exec_progress 0 "Releasing disk..."
    exec_release_disk "$DISK" || return 1
    exec_progress 100 "Disk released."
  else
    log "[=] disk_release: skipped (needs_release=${DISK_NEEDS_RELEASE} approved=${DISK_RELEASE_APPROVED})"
    # mark as done quickly
    exec_progress 100 "Disk release skipped."
  fi
  return 0
}

# ---- main entry ----

execute_install() {
  stage "exec"

  exec_log_config
  exec_require_tools \
    findmnt \
    swapon \
    umount \
    swapoff \
    pvs \
    vgchange \
    dialog || return 1

  # Safety: never touch current environment disk
  if disk_is_current_env_disk "$DISK"; then
    ui_msg "Refusing to run on current environment disk: ${DISK}"
    return 1
  fi

  # Build runner plan
  exec_runner_reset
  exec_runner_add_step "release" "Release disk (umount/swapoff/LVM off)" 10 exec_release_disk_step

  # Далее будут добавляться по мере реализации:
  # exec_runner_add_step "partition" "Partitioning" 20 exec_partition_step
  # exec_runner_add_step "fs" "Create filesystems" 15 exec_mkfs_step
  # exec_runner_add_step "mount" "Mount target" 10 exec_mount_step
  # exec_runner_add_step "bootstrap" "Debootstrap" 25 exec_debootstrap_step
  # exec_runner_add_step "chroot" "Chroot config + GRUB" 20 exec_chroot_step

  exec_runner_run "Installer" "Starting execution...\nLog: ${LOG_FILE}" || return 1

  ui_msg "Execution completed.\nLog: ${LOG_FILE}"
  return 0
}
