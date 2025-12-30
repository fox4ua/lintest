#!/usr/bin/env bash

DISK_CHECK_REASON=""
DISK_CHECK_DETAILS=""

disk_is_current_system_disk() {
  local disk="$1"
  DISK_CHECK_REASON=""
  DISK_CHECK_DETAILS=""

  [[ -b "$disk" ]] || {
    DISK_CHECK_REASON="Некорректный диск"
    DISK_CHECK_DETAILS="$disk не является блочным устройством."
    return 1
  }

  local src_root src_boot src_efi
  src_root="$(findmnt -no SOURCE / 2>/dev/null || true)"
  src_boot="$(findmnt -no SOURCE /boot 2>/dev/null || true)"
  src_efi="$(findmnt -no SOURCE /boot/efi 2>/dev/null || true)"

  if [[ -n "$src_root" && "$src_root" == "$disk"* ]]; then
    DISK_CHECK_REASON="Нельзя выбрать этот диск"
    DISK_CHECK_DETAILS="Текущий / смонтирован из:\n$src_root\n\nВыбранный диск: $disk\n\nЗапусти скрипт из Rescue/Live, а не из установленной системы."
    return 1
  fi

  if [[ -n "$src_boot" && "$src_boot" == "$disk"* ]]; then
    DISK_CHECK_REASON="Нельзя выбрать этот диск"
    DISK_CHECK_DETAILS="Текущий /boot смонтирован из:\n$src_boot\n\nВыбранный диск: $disk\n\nЗапусти скрипт из Rescue/Live."
    return 1
  fi

  if [[ -n "$src_efi" && "$src_efi" == "$disk"* ]]; then
    DISK_CHECK_REASON="Нельзя выбрать этот диск"
    DISK_CHECK_DETAILS="Текущий /boot/efi смонтирован из:\n$src_efi\n\nВыбранный диск: $disk\n\nЗапусти скрипт из Rescue/Live."
    return 1
  fi

  return 0
}
