#!/usr/bin/env bash
set -Eeuo pipefail

has_space_for_data_fs() {
  # Usage:
  #   has_space_for_data_fs <boot_mode_effective> [min_data_gb]
  # Uses globals: DISK ROOT_SIZE EFI_SIZE BOOT_SIZE SWAP_SIZE
  local boot_mode="${1:-bios}"
  local min_data_gb="${2:-1}"

  [[ -n "${DISK:-}" ]] || return 1
  [[ -n "${ROOT_SIZE:-}" ]] || return 1
  [[ -n "${EFI_SIZE:-}" ]] || EFI_SIZE="256"
  [[ -n "${BOOT_SIZE:-}" ]] || BOOT_SIZE="512"
  [[ -n "${SWAP_SIZE:-}" ]] || SWAP_SIZE="0"

  # core calc
  local disk_bytes reserved_bytes root_bytes left_bytes min_bytes

  disk_bytes="$(disk_size_bytes "$DISK" 2>/dev/null || true)" || return 1
  root_bytes="$(root_gb_to_bytes "$ROOT_SIZE" 2>/dev/null || true)" || return 1
  reserved_bytes="$(calc_reserved_bytes "$boot_mode" "$EFI_SIZE" "$BOOT_SIZE" "$SWAP_SIZE" 2>/dev/null || true)" || return 1

  left_bytes=$(( disk_bytes - reserved_bytes - root_bytes ))
  (( left_bytes < 0 )) && left_bytes=0

  min_bytes=$(( min_data_gb * 1024 * 1024 * 1024 ))

  (( left_bytes >= min_bytes ))
}

# -----------------------------
# size helpers
# -----------------------------
size_to_bytes() {
  # accepts: 512M, 1G, 30G, 1024 (MiB), 30GiB, 500MiB (частично)
  # рекомендуемый формат в проекте: 256/512/1024 (MiB), 30G
  local s="${1:-}"
  local n unit

  s="${s// /}"
  [[ -n "$s" ]] || return 1

  # pure number -> MiB
  if [[ "$s" =~ ^[0-9]+$ ]]; then
    n="$s"
    printf '%s\n' $(( n * 1024 * 1024 ))
    return 0
  fi

  # split number and unit
  if [[ "$s" =~ ^([0-9]+)([A-Za-z]+)$ ]]; then
    n="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
  else
    return 1
  fi

  unit="$(echo "$unit" | tr '[:lower:]' '[:upper:]')"

  case "$unit" in
    B)   printf '%s\n' "$n" ;;
    K|KB)   printf '%s\n' $(( n * 1000 )) ;;
    M|MB)   printf '%s\n' $(( n * 1000 * 1000 )) ;;
    G|GB)   printf '%s\n' $(( n * 1000 * 1000 * 1000 )) ;;
    T|TB)   printf '%s\n' $(( n * 1000 * 1000 * 1000 * 1000 )) ;;
    KI|KIB) printf '%s\n' $(( n * 1024 )) ;;
    MI|MIB) printf '%s\n' $(( n * 1024 * 1024 )) ;;
    GI|GIB) printf '%s\n' $(( n * 1024 * 1024 * 1024 )) ;;
    TI|TIB) printf '%s\n' $(( n * 1024 * 1024 * 1024 * 1024 )) ;;
    *) return 1 ;;
  esac
}

root_gb_to_bytes() {
  local s="${1:-}"
  if [[ -z "$s" || ! "$s" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  printf '%s\n' $(( s * 1024 * 1024 * 1024 ))
}

bytes_to_mib() {
  local b="${1:-0}"
  printf '%s\n' $(( (b + 1024*1024 - 1) / (1024*1024) ))
}

disk_size_bytes() {
  local disk="$1"
  if command -v blockdev >/dev/null 2>&1; then
    blockdev --getsize64 "$disk" 2>/dev/null
    return $?
  fi
  if command -v lsblk >/dev/null 2>&1; then
    lsblk -bn -o SIZE "$disk" 2>/dev/null | head -n1
    return $?
  fi
  return 1
}

# -----------------------------
# Calculate reserved bytes (boot/efi/boot/swap + extras + safety)
# Inputs:
#   boot_mode: "uefi"|"bios"
#   efi_size:  e.g. "256" (MiB, used only if uefi)
#   boot_size: e.g. "512" (MiB, always present in your scheme)
#   swap_size: "0"|"1024"|"2048"|"4096" (MiB, or empty -> 0)
#   extras: optional list of size strings (each one adds to reserved)
# Output:
#   prints reserved bytes
# -----------------------------
calc_reserved_bytes() {
  local boot_mode="${1:-bios}"
  local efi_size="${2:-}"
  local boot_size="${3:-}"
  local swap_size="${4:-0}"
  shift 4 || true

  local reserved=0 x

  # Safety/overhead: GPT + alignment + grub + fs metadata buffer
  # (консервативно 256MiB)
  reserved=$(( reserved + 256 * 1024 * 1024 ))

  if [[ "$boot_mode" == "uefi" ]]; then
    [[ -n "$efi_size" ]] || efi_size="256"
    x="$(size_to_bytes "$efi_size")" || return 1
    reserved=$(( reserved + x ))
  fi

  # /boot
  [[ -n "$boot_size" ]] || boot_size="512"
  x="$(size_to_bytes "$boot_size")" || return 1
  reserved=$(( reserved + x ))

  # swap
  if [[ -n "${swap_size:-}" && "${swap_size:-0}" != "0" ]]; then
    x="$(size_to_bytes "$swap_size")" || return 1
    reserved=$(( reserved + x ))
  fi

  # extras (any additional fixed partitions)
  while [[ $# -gt 0 ]]; do
    [[ -n "${1:-}" ]] || { shift; continue; }
    x="$(size_to_bytes "$1")" || return 1
    reserved=$(( reserved + x ))
    shift
  done

  printf '%s\n' "$reserved"
}

# -----------------------------
# Validate that ROOT_SIZE fits into DISK after reserved parts.
# Inputs:
#   disk        : /dev/sda
#   root_size   : e.g. 30 (GiB, digits only)
#   boot_mode   : uefi|bios
#   efi_size    : e.g. 256 (MiB, ignored for bios)
#   boot_size   : e.g. 512 (MiB)
#   swap_size   : 0|1024|2048|4096 (MiB)
#   extras...   : optional list of additional fixed sizes
# Returns:
#   0 ok, 1 error (prints reason)
# -----------------------------
validate_root_fits_disk() {
  local disk="$1"
  local root_size="$2"
  local boot_mode="${3:-bios}"
  local efi_size="${4:-256}"
  local boot_size="${5:-512}"
  local swap_size="${6:-0}"
  shift 6 || true

  local disk_bytes root_bytes reserved_bytes free_bytes

  disk_bytes="$(disk_size_bytes "$disk" 2>/dev/null || true)"
  if [[ -z "$disk_bytes" || ! "$disk_bytes" =~ ^[0-9]+$ || "$disk_bytes" -le 0 ]]; then
    echo "ERROR: cannot determine disk size for $disk"
    return 1
  fi

  root_bytes="$(root_gb_to_bytes "$root_size" 2>/dev/null || true)"
  if [[ -z "$root_bytes" || ! "$root_bytes" =~ ^[0-9]+$ || "$root_bytes" -le 0 ]]; then
    echo "ERROR: invalid ROOT_SIZE: '$root_size' (use GB number like 30)"
    return 1
  fi

  reserved_bytes="$(calc_reserved_bytes "$boot_mode" "$efi_size" "$boot_size" "$swap_size" "$@" 2>/dev/null || true)"
  if [[ -z "$reserved_bytes" || ! "$reserved_bytes" =~ ^[0-9]+$ ]]; then
    echo "ERROR: failed to calculate reserved bytes"
    return 1
  fi

  free_bytes=$(( disk_bytes - reserved_bytes ))
  if (( free_bytes < 0 )); then
    free_bytes=0
  fi

  if (( root_bytes > free_bytes )); then
    echo "ERROR: root size does not fit."
    echo "  disk     : $disk ($(bytes_to_mib "$disk_bytes") MiB)"
    echo "  reserved : $(bytes_to_mib "$reserved_bytes") MiB (efi/boot/swap/extras + safety)"
    echo "  free     : $(bytes_to_mib "$free_bytes") MiB available for root+data"
    echo "  root req : $(bytes_to_mib "$root_bytes") MiB"
    return 1
  fi

  return 0
}
