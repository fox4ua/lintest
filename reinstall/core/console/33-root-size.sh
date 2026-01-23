#!/usr/bin/env bash
set -Eeuo pipefail

# Требуется:
#   DISK, BOOT_MODE, EFI_SIZE, BOOT_SIZE, SWAP_SIZE
#   source "$BASE_DIR/init/20-size-checks.sh"

ui_pick_root_size_console() {
  local out_var="$1"

  local default_gb="30"
  local ans root_gb root_size
  local disk_bytes reserved_bytes free_bytes max_gb

  local boot_mode_effective

  # базовые проверки контекста
  if [[ -z "${DISK:-}" ]]; then
    echo "ERROR: DISK is not set"
    return 1
  fi
  if [[ -z "${BOOT_MODE:-}" ]]; then
    echo "ERROR: BOOT_MODE is not set"
    return 1
  fi

  [[ -n "${BOOT_SIZE:-}" ]] || BOOT_SIZE="512M"
  [[ -n "${SWAP_SIZE:-}" ]] || SWAP_SIZE="0"
  [[ -n "${EFI_SIZE:-}"  ]] || EFI_SIZE="256M"

  # BOOT_MODE can be: uefi|bios|auto
  case "$BOOT_MODE" in
    uefi|bios) boot_mode_effective="$BOOT_MODE" ;;
    auto)
      if [[ -d /sys/firmware/efi ]]; then
        boot_mode_effective="uefi"
      else
        boot_mode_effective="bios"
      fi
      ;;
    *)
      echo "ERROR: invalid BOOT_MODE='$BOOT_MODE' (expected: uefi|bios|auto)"
      return 1
      ;;
  esac

  # вычисляем максимум (disk - reserved)
  disk_bytes="$(disk_size_bytes "$DISK" 2>/dev/null || true)"
  if [[ -z "$disk_bytes" || ! "$disk_bytes" =~ ^[0-9]+$ || "$disk_bytes" -le 0 ]]; then
    echo "ERROR: cannot determine disk size for $DISK"
    return 1
  fi

  reserved_bytes="$(calc_reserved_bytes "$boot_mode_effective" "$EFI_SIZE" "$BOOT_SIZE" "$SWAP_SIZE" 2>/dev/null || true)"
  if [[ -z "$reserved_bytes" || ! "$reserved_bytes" =~ ^[0-9]+$ ]]; then
    echo "ERROR: failed to calculate reserved size"
    return 1
  fi

  free_bytes=$(( disk_bytes - reserved_bytes ))
  (( free_bytes < 0 )) && free_bytes=0

  # max in GiB (floor)
  max_gb=$(( free_bytes / (1024 * 1024 * 1024) ))
  if (( max_gb < 1 )); then
    echo "ERROR: not enough free space for root (need at least 1 GiB)."
    return 1
  fi

  while true; do
    echo "Root size (--root-size) [GB only]"
    echo "  Disk:       ${DISK}"
    echo "  Boot mode:  ${BOOT_MODE} (effective: ${boot_mode_effective})"
    echo "  Reserved:   $(bytes_to_mib "$reserved_bytes") MiB (efi/boot/swap + safety)"
    echo "  Max root:   ${max_gb} GB"
    echo "  Default:    ${default_gb} GB"
    echo "  Enter 0 to Cancel"
    printf "Root size in GB [%s]: " "$default_gb"
    read -r ans

    [[ "$ans" == "0" ]] && return 1
    [[ -n "$ans" ]] || ans="$default_gb"

    # только цифры
    if [[ ! "$ans" =~ ^[0-9]+$ ]]; then
      echo "Invalid input. Digits only."
      echo
      continue
    fi

    root_gb="$ans"
    (( root_gb >= 1 )) || { echo "Root size must be >= 1 GB."; echo; continue; }

    if (( root_gb > max_gb )); then
      echo "Too large. Max root is ${max_gb} GB."
      echo
      continue
    fi

    root_size="${root_gb}G"

    # финальная проверка (страховка)
    if ! validate_root_fits_disk "$DISK" "$root_size" "$boot_mode_effective" "$EFI_SIZE" "$BOOT_SIZE" "$SWAP_SIZE"; then
      echo
      echo "Choose a smaller root size."
      echo
      continue
    fi

    printf -v "$out_var" '%s' "$root_size"
    return 0
  done
}
