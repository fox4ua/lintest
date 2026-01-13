#!/usr/bin/env bash

exec_install_deps() {
  local -a required=(
    parted wipefs blkid mkfs.ext4 mkswap chroot debootstrap
    partprobe udevadm blockdev dd mount umount timeout
  )

  if [[ "${BOOT_MODE:-}" == "uefi" ]]; then
    required+=(mkfs.vfat)
  fi
  if [[ "${LVM_MODE:-none}" != "none" ]]; then
    required+=(pvcreate vgcreate lvcreate vgchange pvs vgs)
  fi

  local -a missing=()
  local cmd
  for cmd in "${required[@]}"; do
    require_cmd "$cmd" || missing+=("$cmd")
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  if ! require_cmd apt-get; then
    fatal "Missing required commands: ${missing[*]}. apt-get is not available to install them."
  fi

  export DEBIAN_FRONTEND=noninteractive
  run apt-get update || fatal "apt-get update failed (no network / broken mirror?)."

  local -a pkgs=()
  local item
  for item in "${missing[@]}"; do
    case "$item" in
      parted) array_add_unique parted pkgs ;;
      wipefs|blkid|mkswap|partprobe|mount|umount|blockdev) array_add_unique util-linux pkgs ;;
      mkfs.ext4) array_add_unique e2fsprogs pkgs ;;
      mkfs.vfat) array_add_unique dosfstools pkgs ;;
      debootstrap) array_add_unique debootstrap pkgs ;;
      pvcreate|vgcreate|lvcreate|vgchange|pvs|vgs) array_add_unique lvm2 pkgs ;;
      chroot|dd|timeout) array_add_unique coreutils pkgs ;;
      udevadm) array_add_unique udev pkgs ;;
    esac
  done

  if [[ ${#pkgs[@]} -gt 0 ]]; then
    run apt-get install -y --no-install-recommends "${pkgs[@]}" || fatal "Failed to install required packages: ${pkgs[*]}"
  fi

  missing=()
  for cmd in "${required[@]}"; do
    require_cmd "$cmd" || missing+=("$cmd")
  done
  [[ ${#missing[@]} -eq 0 ]] || fatal "Still missing required commands: ${missing[*]}"
}
