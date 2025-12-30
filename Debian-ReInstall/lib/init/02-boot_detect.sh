#!/usr/bin/env bash

# detect_boot_mode_strict
# return 0 -> UEFI реально доступен в текущем окружении (Rescue/Live)
# return 1 -> UEFI недоступен (загрузились в Legacy или efivars недоступны)
detect_boot_mode_strict() {
  # базовый индикатор: каталог efi должен существовать
  [[ -d /sys/firmware/efi ]] || return 1

  # efivars должен быть доступен (иначе grub-efi/efibootmgr часто бесполезны)
  if [[ -d /sys/firmware/efi/efivars ]]; then
    return 0
  fi

  # иногда efivars появляется после монтирования efivarfs
  if command -v mount >/dev/null 2>&1; then
    if ! mountpoint -q /sys/firmware/efi/efivars 2>/dev/null; then
      mount -t efivarfs efivarfs /sys/firmware/efi/efivars >/dev/null 2>&1 || true
    fi
  fi

  [[ -d /sys/firmware/efi/efivars ]] || return 1
  return 0
}
