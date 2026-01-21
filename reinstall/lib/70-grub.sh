#!/usr/bin/env bash
# shellcheck shell=bash

# GRUB install/update helper.
#
# Inputs (globals):
#   TARGET, BOOT_MODE, DISK
#
# Requires:
#   log() (lib/00-log.sh)

grub_install_and_update() {
  log "Installing GRUB..."

  if [[ "${BOOT_MODE}" == "uefi" ]]; then
    chroot "${TARGET}" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck --no-nvram
  else
    chroot "${TARGET}" grub-install --target=i386-pc --recheck "${DISK}"
  fi

  chroot "${TARGET}" update-grub
}
