#!/usr/bin/env bash

grub_target_uefi() {
  local arch="$1"
  case "$arch" in
    amd64) echo "x86_64-efi" ;;
    i386) echo "i386-efi" ;;
    arm64) echo "arm64-efi" ;;
    armhf) echo "arm-efi" ;;
    *) return 1 ;;
  esac
}

grub_target_bios() {
  local arch="$1"
  case "$arch" in
    amd64|i386) echo "i386-pc" ;;
    *) return 1 ;;
  esac
}

install_bootloader() {
  stage "bootloader"

  local arch target
  arch="$(detect_arch)"
  [[ -n "$arch" ]] || fatal "Unable to detect target architecture for bootloader"

  case "$BOOT_MODE" in
    uefi)
      target="$(grub_target_uefi "$arch")" || fatal "Unsupported architecture for UEFI GRUB: $arch"
      [[ -d "$TARGET_DIR/boot/efi" ]] || fatal "EFI dir not found in target"
      chroot_run "grub-install --target=$target --efi-directory=/boot/efi --bootloader-id=debian --recheck --no-nvram"
      chroot_run "grub-install --target=$target --efi-directory=/boot/efi --bootloader-id=debian --recheck --removable"
      ;;
    biosgpt|biosmbr|*)
      target="$(grub_target_bios "$arch")" || fatal "Unsupported architecture for BIOS GRUB: $arch"
      chroot_run "grub-install --target=$target --recheck $DISK"
      ;;
  esac

  chroot_run "update-grub"
}
