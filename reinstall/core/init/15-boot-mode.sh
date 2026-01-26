#!/usr/bin/env bash
set -Eeuo pipefail

boot_mode_effective_get() {
  # Prints: uefi|bios
  # Uses globals: BOOT_MODE, BOOT_MODE_EFFECTIVE, BOOT_MODE_AUTO_EFFECTIVE
  local m="${BOOT_MODE:-auto}"
  local eff=""

  case "$m" in
    uefi|bios)
      printf '%s\n' "$m"
      return 0
      ;;
    auto)
      if [[ -n "${BOOT_MODE_EFFECTIVE:-}" ]]; then
        eff="$BOOT_MODE_EFFECTIVE"
      elif [[ -n "${BOOT_MODE_AUTO_EFFECTIVE:-}" ]]; then
        eff="$BOOT_MODE_AUTO_EFFECTIVE"
      elif [[ -d /sys/firmware/efi ]]; then
        eff="uefi"
      else
        eff="bios"
      fi
      ;;
    *)
      return 1
      ;;
  esac

  [[ "$eff" == "uefi" || "$eff" == "bios" ]] || return 1
  printf '%s\n' "$eff"
}
