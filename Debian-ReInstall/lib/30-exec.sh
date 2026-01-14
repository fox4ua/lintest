#!/usr/bin/env bash
# shellcheck shell=bash

: "${EXEC_DIR:?}"

# exec core
source "$EXEC_DIR/00-common.sh"
source "$EXEC_DIR/10-runner.sh"

# exec steps (подключай по мере реализации)
source "$EXEC_DIR/15-release_disk.sh"
source "$EXEC_DIR/20-partition.sh"
source "$EXEC_DIR/25-lvm.sh"
source "$EXEC_DIR/30-mkfs.sh"
source "$EXEC_DIR/35-mount.sh"
source "$EXEC_DIR/40-debootstrap.sh"
source "$EXEC_DIR/45-chroot_mounts.sh"
source "$EXEC_DIR/50-chroot_dns.sh"
source "$EXEC_DIR/55-apt_install.sh"
# ---- step wrappers for runner ----

exec_release_disk_step() {
  exec_progress 0 "Releasing disk (unmount/swapoff/dm/LVM)..."
  exec_release_disk "$DISK" || return 1
  exec_progress 100 "Disk released."
  return 0
}

exec_partition_step() {
  exec_partition_disk "$DISK" || return 1
  return 0
}

exec_lvm_step() {
  if [[ "${LVM_MODE}" == "none" ]]; then
    exec_progress 100 "LVM skipped (none)."
    return 0
  fi
  exec_lvm_create || return 1
  return 0
}

exec_mkfs_step() {
  exec_mkfs_all || return 1
  return 0
}

exec_mount_step() {
  exec_mount_target || return 1
  return 0
}

exec_debootstrap_step() {
  exec_debootstrap || return 1
  return 0
}

exec_chroot_mounts_step() {
  exec_progress 0 "Mounting chroot filesystems..."
  exec_chroot_mounts_up || return 1
  exec_progress 100 "Chroot mounts ready."
  return 0
}

exec_chroot_dns_step() {
  exec_progress 0 "Applying resolv.conf inside target..."
  exec_chroot_dns_apply || return 1
  exec_progress 100 "Chroot DNS ready."
  return 0
}

exec_apt_install_step() {
  exec_apt_install_all || return 1
  return 0
}

# ---- main entry ----

execute_install() {
  stage "exec"

  exec_log_config
  exec_require_tools \
    dialog \
    lsblk \
    blkid \
    findmnt \
    swapon \
    umount \
    swapoff \
    pvs \
    vgchange \
    dmsetup \
    blockdev \
    partx \
    udevadm \
    wipefs \
    sfdisk || return 1

  if [[ "${BOOT_MODE}" == "uefi" || "${BOOT_MODE}" == "biosgpt" ]]; then
    exec_require_tools sgdisk || return 1
  fi

  # Safety: never touch current environment disk
  if disk_is_current_env_disk "$DISK"; then
    ui_msg "Refusing to run on current environment disk: ${DISK}"
    return 1
  fi

  # Build runner plan
  exec_runner_reset
  exec_runner_add_step "release"  "Release disk (umount/swapoff/LVM off)"     10 exec_release_disk_step
  exec_runner_add_step "partition" "Partition disk (GPT/MBR)"                 20 exec_partition_step
  exec_runner_add_step "lvm" "Create LVM (PV/VG/LV root)"                     15 exec_lvm_step
  exec_runner_add_step "mkfs" "Create filesystems (EFI/boot/root/swap)"       15 exec_mkfs_step
  exec_runner_add_step "mount" "Mount target filesystem tree"                 10 exec_mount_step
  exec_runner_add_step "debootstrap" "Debootstrap base system"                25 exec_debootstrap_step
  exec_runner_add_step "chroot_mounts" "Chroot mounts (/dev,/proc,/sys,/run)" 8  exec_chroot_mounts_step
  exec_runner_add_step "chroot_dns"    "Chroot DNS (resolv.conf)"             2  exec_chroot_dns_step
  exec_runner_add_step "apt" "APT + base packages + kernel + GRUB"            25 exec_apt_install_step

  exec_runner_run "Installer" "Starting execution...\nLog: ${LOG_FILE}" || return 1

  ui_msg "Execution completed (steps: release + partition).\n\nNext: filesystems + mount + debootstrap + chroot.\n\nLog: ${LOG_FILE}"
  return 0
}
