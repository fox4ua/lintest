#!/usr/bin/env bash

disk_is_current_env_disk() {
  local disk="$1"
  local src

  src="$(findmnt -no SOURCE / 2>/dev/null || true)"
  [[ -n "$src" && "$src" == "$disk"* ]] && return 0

  src="$(findmnt -no SOURCE /boot 2>/dev/null || true)"
  [[ -n "$src" && "$src" == "$disk"* ]] && return 0

  src="$(findmnt -no SOURCE /boot/efi 2>/dev/null || true)"
  [[ -n "$src" && "$src" == "$disk"* ]] && return 0

  return 1
}
