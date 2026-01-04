#!/usr/bin/env bash

validate_partition_sizes() {
  local disk_bytes boot_bytes swap_bytes root_bytes required_bytes

  disk_bytes="$(disk_get_size_bytes "$DISK" || true)"
  if [[ -z "$disk_bytes" ]]; then
    log "[!] disk size check skipped: lsblk unavailable or size unknown"
    return 0
  fi

  boot_bytes=$(( BOOT_SIZE_MIB * 1024 * 1024 ))
  swap_bytes=$(( SWAP_SIZE_GIB * 1024 * 1024 * 1024 ))
  if (( ROOT_SIZE_GIB == 0 )); then
    required_bytes=$(( boot_bytes + swap_bytes ))
  else
    root_bytes=$(( ROOT_SIZE_GIB * 1024 * 1024 * 1024 ))
    required_bytes=$(( boot_bytes + swap_bytes + root_bytes ))
  fi

  if (( required_bytes > disk_bytes )); then
    ui_msg "Выбранные размеры разделов превышают размер диска.\n\nДиск: ${DISK}\nРазмер диска: $(( disk_bytes / 1024 / 1024 / 1024 )) GiB\nТребуется: $(( required_bytes / 1024 / 1024 / 1024 )) GiB\n\nПожалуйста, уменьшите размеры разделов."
    return 1
  fi

  return 0
}