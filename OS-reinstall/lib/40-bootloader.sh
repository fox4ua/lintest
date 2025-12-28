#!/usr/bin/env bash
set -Eeuo pipefail

bootloader_assert_bios_grub_present() {
  local disk="$1"
  if ! parted -s "$disk" print 2>/dev/null | awk '
    BEGIN{found=0}
    $1 ~ /^[0-9]+$/ {
      part=$1
      if(part==1 && $0 ~ /bios_grub/) found=1
    }
    END{exit(found?0:1)}
  '; then
    warn "bios_grub partition not detected on ${disk} (p1). GRUB may fail on GPT+BIOS."
  fi
}

bootloader_install() {
  local boot_mode="$1" disk="$2"

  log "Installing bootloader in chroot (mode=${boot_mode})"

  if [[ "$boot_mode" == "uefi" ]]; then
    if ! chroot /mnt findmnt -rn /boot/efi >/dev/null 2>&1; then
      die "UEFI mode: /boot/efi is not mounted in target. Cannot install grub-efi."
    fi

    run chroot /mnt bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y purge grub-pc grub-pc-bin grub2-common 2>/dev/null || true"
    run chroot /mnt bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y autoremove 2>/dev/null || true"

    run chroot /mnt bash -c "DEBIAN_FRONTEND=noninteractive apt-get update -y"
    run chroot /mnt bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y grub-efi-amd64 efibootmgr"

    run chroot /mnt grub-install       --target=x86_64-efi       --efi-directory=/boot/efi       --bootloader-id=debian       --recheck

    run chroot /mnt update-grub
  else
    bootloader_assert_bios_grub_present "$disk"

    run chroot /mnt bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y purge grub-efi-amd64 grub-efi-amd64-bin shim-signed 2>/dev/null || true"
    run chroot /mnt bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y autoremove 2>/dev/null || true"

    run chroot /mnt bash -c "DEBIAN_FRONTEND=noninteractive apt-get update -y"
    run chroot /mnt bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y grub-pc"

    run chroot /mnt grub-install --target=i386-pc "$disk"
    run chroot /mnt update-grub
  fi

  log "Bootloader installed successfully"
}
