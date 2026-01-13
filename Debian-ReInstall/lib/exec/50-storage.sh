#!/usr/bin/env bash

lvm_prepare_root() {
  ROOT_DEV="$PART_ROOT"

  if [[ "$LVM_MODE" == "none" ]]; then
    return 0
  fi

  require_cmd pvcreate || fatal "lvm2 not available (pvcreate)"

  stage "lvm"
  log "[=] LVM mode: $LVM_MODE"

  run wipefs -a "$PART_ROOT" || true
  run pvcreate -ff -y "$PART_ROOT"
  run vgcreate "$VG_NAME" "$PART_ROOT"

  case "$LVM_MODE" in
    linear)
      if (( ROOT_SIZE_GIB == 0 )); then
        run lvcreate -l 100%FREE --wipesignatures y -y -n root "$VG_NAME"
      else
        local vg_free_bytes requested_bytes
        vg_free_bytes=$(vgs --noheadings --units b -o vg_free "$VG_NAME" 2>/dev/null | awk '{gsub(/[^0-9]/,"",$1);print $1;exit}')
        requested_bytes=$(( ROOT_SIZE_GIB * 1024 * 1024 * 1024 ))
        if [[ -n "$vg_free_bytes" && "$vg_free_bytes" =~ ^[0-9]+$ && $requested_bytes -ge $vg_free_bytes ]]; then
          log "[!] Requested root size ${ROOT_SIZE_GIB}G exceeds available space; using 100%FREE instead."
          run lvcreate -l 100%FREE --wipesignatures y -y -n root "$VG_NAME"
        else
          run lvcreate -L "${ROOT_SIZE_GIB}G" --wipesignatures y -y -n root "$VG_NAME"
        fi
      fi
      ROOT_DEV="/dev/${VG_NAME}/root"
      ;;
    thin)
      run lvcreate -l 100%FREE --type thin-pool -y -n "$THINPOOL_NAME" "$VG_NAME"

      local vsize_g
      if (( ROOT_SIZE_GIB == 0 )); then
        vsize_g=$(pvs --noheadings --units g -o pv_size "$PART_ROOT" 2>/dev/null | awk '{gsub(/[^0-9.]/,"",$1);print $1}' | head -n1)
        vsize_g=${vsize_g%.*}
        [[ -n "$vsize_g" && "$vsize_g" =~ ^[0-9]+$ ]] || vsize_g=20
      else
        vsize_g="$ROOT_SIZE_GIB"
      fi

      run lvcreate -V "${vsize_g}G" -T "${VG_NAME}/${THINPOOL_NAME}" --wipesignatures y -y -n root
      ROOT_DEV="/dev/${VG_NAME}/root"
      ;;
    *)
      fatal "Unknown LVM_MODE: $LVM_MODE"
      ;;
  esac
}

mkfs_and_mount() {
  stage "mkfs"
  mkdir -p "$TARGET_DIR"

  require_cmd mkfs.ext4 || fatal "mkfs.ext4 not found"
  run mkfs.ext4 -F "$PART_BOOT"

  if [[ -n "${PART_SWAP:-}" ]]; then
    run mkswap "$PART_SWAP"
  fi

  run mkfs.ext4 -F "$ROOT_DEV"

  if [[ "$BOOT_MODE" == "uefi" ]]; then
    require_cmd mkfs.vfat || fatal "mkfs.vfat not found (dosfstools)"
    run mkfs.vfat -F 32 "$PART_EFI"
  fi

  stage "mount"
  run mount "$ROOT_DEV" "$TARGET_DIR"
  mkdir -p "$TARGET_DIR/boot"
  run mount "$PART_BOOT" "$TARGET_DIR/boot"
  if [[ "$BOOT_MODE" == "uefi" ]]; then
    mkdir -p "$TARGET_DIR/boot/efi"
    run mount "$PART_EFI" "$TARGET_DIR/boot/efi"
  fi
}

write_fstab() {
  stage "fstab"
  require_cmd blkid || fatal "blkid not found"
  local root_uuid boot_uuid swap_uuid efi_uuid

  root_uuid=$(blkid -s UUID -o value "$ROOT_DEV" 2>/dev/null || true)
  boot_uuid=$(blkid -s UUID -o value "$PART_BOOT" 2>/dev/null || true)
  [[ -n "${PART_SWAP:-}" ]] && swap_uuid=$(blkid -s UUID -o value "$PART_SWAP" 2>/dev/null || true)
  [[ "$BOOT_MODE" == "uefi" ]] && efi_uuid=$(blkid -s UUID -o value "$PART_EFI" 2>/dev/null || true)

  [[ -n "$root_uuid" ]] || fatal "Failed to read UUID for root device: $ROOT_DEV"
  [[ -n "$boot_uuid" ]] || fatal "Failed to read UUID for boot partition: $PART_BOOT"
  if [[ "$BOOT_MODE" == "uefi" ]]; then
    [[ -n "${efi_uuid:-}" ]] || fatal "Failed to read UUID for EFI partition: $PART_EFI"
  fi

  mkdir -p "$TARGET_DIR/etc"
  {
    echo "# /etc/fstab"
    echo "UUID=${root_uuid} / ext4 defaults 0 1"
    echo "UUID=${boot_uuid} /boot ext4 defaults 0 2"
    if [[ "$BOOT_MODE" == "uefi" ]]; then
      echo "UUID=${efi_uuid} /boot/efi vfat umask=0077 0 1"
    fi
    if [[ -n "${PART_SWAP:-}" ]]; then
      echo "UUID=${swap_uuid} none swap sw 0 0"
    fi
  } >"$TARGET_DIR/etc/fstab"
}
