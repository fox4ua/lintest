#!/usr/bin/env bash

install_bootloader() {
  stage "bootloader"

  # GRUB install must run inside chroot to pick up installed grub packages.
  case "$BOOT_MODE" in
    uefi)
      # Ensure EFI is mounted
      [[ -d "$TARGET_DIR/boot/efi" ]] || fatal "EFI dir not found in target"
      chroot_run "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck --no-nvram"
      # fallback path, makes it boot on most UEFI systems even without NVRAM update
      chroot_run "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck --removable"
      ;;
    *)
      chroot_run "grub-install --target=i386-pc --recheck $DISK"
      ;;
  esac

  chroot_run "update-grub"
}
