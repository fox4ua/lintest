#!/usr/bin/env bash

validate_partition_sizes() {
  local disk_bytes boot_bytes swap_bytes root_bytes required_bytes extra_bytes overhead_bytes
  local mbr_limit_bytes

  disk_bytes="$(disk_get_size_bytes "$DISK" || true)"
  if [[ -z "$disk_bytes" ]]; then
    log "[!] disk size check skipped: lsblk unavailable or size unknown"
    return 0
  fi

  boot_bytes=$(( BOOT_SIZE_MIB * 1024 * 1024 ))
  swap_bytes=$(( SWAP_SIZE_GIB * 1024 * 1024 * 1024 ))
  overhead_bytes=$(( 16 * 1024 * 1024 ))
  case "$BOOT_MODE" in
    uefi)
      extra_bytes=$(( EFI_SIZE_MIB * 1024 * 1024 ))
      ;;
    biosgpt)
      extra_bytes=$(( 2 * 1024 * 1024 ))
      ;;
    biosmbr|*)
      extra_bytes=0
      ;;
  esac

  if [[ "$BOOT_MODE" == "biosmbr" ]]; then
    mbr_limit_bytes=$(( 2 * 1024 * 1024 * 1024 * 1024 ))
    if (( disk_bytes > mbr_limit_bytes )); then
      ui_msg "Выбран Legacy BIOS + MBR, но размер диска превышает 2 TiB.\n\nMBR не поддерживает такие диски для загрузки. Выберите режим UEFI + GPT или Legacy BIOS + GPT."
      return 1
    fi
  fi
  if (( ROOT_SIZE_GIB == 0 )); then
    required_bytes=$(( boot_bytes + swap_bytes + extra_bytes + overhead_bytes ))
  else
    root_bytes=$(( ROOT_SIZE_GIB * 1024 * 1024 * 1024 ))
    required_bytes=$(( boot_bytes + swap_bytes + root_bytes + extra_bytes + overhead_bytes ))
  fi

  if (( required_bytes > disk_bytes )); then
    ui_msg "Выбранные размеры разделов превышают размер диска.\n\nДиск: ${DISK}\nРазмер диска: $(( disk_bytes / 1024 / 1024 / 1024 )) GiB\nТребуется: $(( required_bytes / 1024 / 1024 / 1024 )) GiB\n\nВ расчёт включены служебные разделы (ESP/bios_grub) и запас под GPT/выравнивание.\nПожалуйста, уменьшите размеры разделов."
    return 1
  fi

  return 0
}
