#!/usr/bin/env bash

execute_install() {
  stage "execute"

  # Basic preflight
  [[ -n "${DISK:-}" ]] || fatal "DISK is not set"
  [[ -b "${DISK:-}" ]] || fatal "DISK is not a block device: $DISK"
  [[ -n "${BOOT_MODE:-}" ]] || fatal "BOOT_MODE is not set"
  [[ -n "${DEBIAN_SUITE:-}" ]] || fatal "DEBIAN_SUITE is not set"
  [[ -n "${DEBIAN_MIRROR:-}" ]] || fatal "DEBIAN_MIRROR is not set"

  # Ensure commands exist
  exec_install_deps

  # Always clean on exit from execute
  trap 'exec_cleanup' EXIT

  disk_release_resources
  disk_wipe
  disk_partition
  lvm_prepare_root
  mkfs_and_mount
  write_fstab

  debootstrap_install
  write_sources_list
  install_base_packages
  write_hostname_hosts
  write_network_config
  set_root_password
  install_bootloader

  stage "done"
}
