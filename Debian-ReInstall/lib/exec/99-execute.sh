#!/usr/bin/env bash

execute_install() {
  stage "execute"

  preflight_validate_env
  exec_install_deps

  exec_net_check_host

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
