#!/usr/bin/env bash
# shellcheck shell=bash

# Partitioning step.
# Produces variables for next steps:
#   PART_EFI, PART_BIOS_GRUB, PART_BOOT, PART_SWAP, PART_ROOT, PART_PV

exec_partition_disk() {
  local disk="$1"

  [[ -n "$disk" && -b "$disk" ]] || {
    log "[!] partition: invalid disk: $disk"
    return 1
  }

  if disk_is_current_env_disk "$disk"; then
    log "[!] partition: refusing to operate on current environment disk: $disk"
    ui_msg "Refusing to operate on current environment disk: ${disk}"
    return 1
  fi

  PART_EFI=""
  PART_BIOS_GRUB=""
  PART_BOOT=""
  PART_SWAP=""
  PART_ROOT=""
  PART_PV=""

  exec_progress 5 "Wiping signatures..."

  # Best-effort wipe (tables + fs signatures)
  if [[ "$BOOT_MODE" == "uefi" || "$BOOT_MODE" == "biosgpt" ]]; then
    if command -v sgdisk >/dev/null 2>&1; then
      exec_try sgdisk --zap-all "$disk"
    fi
  else
    if command -v sfdisk >/dev/null 2>&1; then
      exec_try sfdisk --delete "$disk"
    fi
  fi

  if command -v wipefs >/dev/null 2>&1; then
    exec_try wipefs -a "$disk"
  fi

  exec_progress 15 "Creating partition table..."

  case "$BOOT_MODE" in
    uefi|biosgpt)
      exec_partition_gpt "$disk"
      ;;
    biosmbr)
      exec_partition_mbr "$disk"
      ;;
    *)
      log "[!] partition: unknown BOOT_MODE=${BOOT_MODE}"
      return 1
      ;;
  esac

  exec_progress 80 "Reloading partition table..."
  exec_refresh_parttable "$disk"

  exec_progress 90 "Waiting for devices..."
  exec_partition_wait_devices "$disk" || return 1

  export PART_EFI PART_BIOS_GRUB PART_BOOT PART_SWAP PART_ROOT PART_PV

  log "[=] partitions: EFI=${PART_EFI:-none} BIOS_GRUB=${PART_BIOS_GRUB:-none} BOOT=${PART_BOOT:-none} SWAP=${PART_SWAP:-none} ROOT=${PART_ROOT:-none} PV=${PART_PV:-none}"

  exec_progress 100 "Partitioning done."
  return 0
}

exec_partition_gpt() {
  local disk="$1"
  local n=0
  local idx_boot idx_swap idx_root
  local swap_gib="${SWAP_SIZE_GIB:-0}"
  local root_gib="${ROOT_SIZE_GIB:-0}"
  local boot_mib="${BOOT_SIZE_MIB:-512}"
  local efi_mib="${EFI_SIZE_MIB:-512}"

  command -v sgdisk >/dev/null 2>&1 || {
    ui_msg "sgdisk is required for GPT partitioning. Install package: gdisk"
    log "[!] partition: sgdisk not found"
    return 1
  }

  # New GPT
  exec_run sgdisk -o "$disk"

  if [[ "$BOOT_MODE" == "uefi" ]]; then
    n=1
    exec_progress 20 "Creating EFI System Partition (${efi_mib}MiB)..."
    exec_run sgdisk -n ${n}:1MiB:+${efi_mib}MiB -t ${n}:ef00 -c ${n}:"EFI" "$disk"
    PART_EFI="$(exec_part_path "$disk" "$n")"
    idx_boot=2
  else
    # BIOS + GPT requires bios_grub
    n=1
    exec_progress 20 "Creating BIOS boot partition (2MiB)..."
    exec_run sgdisk -n ${n}:1MiB:+2MiB -t ${n}:ef02 -c ${n}:"BIOSBOOT" "$disk"
    PART_BIOS_GRUB="$(exec_part_path "$disk" "$n")"
    idx_boot=2
  fi

  # /boot
  exec_progress 30 "Creating /boot partition (${boot_mib}MiB)..."
  exec_run sgdisk -n ${idx_boot}:0:+${boot_mib}MiB -t ${idx_boot}:8300 -c ${idx_boot}:"boot" "$disk"
  PART_BOOT="$(exec_part_path "$disk" "$idx_boot")"

  idx_swap=$(( idx_boot + 1 ))
  idx_root=$(( idx_boot + 1 ))

  # swap (optional)
  if (( swap_gib > 0 )); then
    exec_progress 40 "Creating swap partition (${swap_gib}GiB)..."
    exec_run sgdisk -n ${idx_swap}:0:+${swap_gib}GiB -t ${idx_swap}:8200 -c ${idx_swap}:"swap" "$disk"
    PART_SWAP="$(exec_part_path "$disk" "$idx_swap")"
    idx_root=$(( idx_swap + 1 ))
  fi

  # root or LVM PV
  if [[ "${LVM_MODE}" == "none" ]]; then
    exec_progress 55 "Creating root partition..."
    if (( root_gib == 0 )); then
      exec_run sgdisk -n ${idx_root}:0:0 -t ${idx_root}:8300 -c ${idx_root}:"root" "$disk"
    else
      exec_run sgdisk -n ${idx_root}:0:+${root_gib}GiB -t ${idx_root}:8300 -c ${idx_root}:"root" "$disk"
    fi
    PART_ROOT="$(exec_part_path "$disk" "$idx_root")"
  else
    exec_progress 55 "Creating LVM PV partition..."
    if (( root_gib == 0 )); then
      exec_run sgdisk -n ${idx_root}:0:0 -t ${idx_root}:8e00 -c ${idx_root}:"pv" "$disk"
    else
      exec_run sgdisk -n ${idx_root}:0:+${root_gib}GiB -t ${idx_root}:8e00 -c ${idx_root}:"pv" "$disk"
    fi
    PART_PV="$(exec_part_path "$disk" "$idx_root")"
  fi

  exec_try sgdisk -p "$disk"
  return 0
}

exec_partition_mbr() {
  local disk="$1"
  local swap_gib="${SWAP_SIZE_GIB:-0}"
  local root_gib="${ROOT_SIZE_GIB:-0}"
  local boot_mib="${BOOT_SIZE_MIB:-512}"

  command -v sfdisk >/dev/null 2>&1 || {
    ui_msg "sfdisk is required for MBR partitioning (util-linux)."
    log "[!] partition: sfdisk not found"
    return 1
  }

  local swap_mib=$(( swap_gib * 1024 ))
  local root_mib=0
  if (( root_gib > 0 )); then
    root_mib=$(( root_gib * 1024 ))
  fi

  exec_progress 25 "Creating MBR partition table..."

  # Part numbers: 1=/boot, 2=swap (optional), 3=root/pv
  local ptype_root="83"
  if [[ "${LVM_MODE}" != "none" ]]; then
    ptype_root="8e"
  fi

  if (( swap_gib > 0 )); then
    if (( root_gib == 0 )); then
      exec_run sfdisk "$disk" <<EOF_SFDISK
label: dos
unit: MiB

1 : start=1, size=${boot_mib}, type=83, bootable
2 : size=${swap_mib}, type=82
3 : type=${ptype_root}
EOF_SFDISK
    else
      exec_run sfdisk "$disk" <<EOF_SFDISK
label: dos
unit: MiB

1 : start=1, size=${boot_mib}, type=83, bootable
2 : size=${swap_mib}, type=82
3 : size=${root_mib}, type=${ptype_root}
EOF_SFDISK
    fi
    PART_BOOT="$(exec_part_path "$disk" 1)"
    PART_SWAP="$(exec_part_path "$disk" 2)"
    if [[ "${LVM_MODE}" == "none" ]]; then
      PART_ROOT="$(exec_part_path "$disk" 3)"
    else
      PART_PV="$(exec_part_path "$disk" 3)"
    fi
  else
    if (( root_gib == 0 )); then
      exec_run sfdisk "$disk" <<EOF_SFDISK
label: dos
unit: MiB

1 : start=1, size=${boot_mib}, type=83, bootable
2 : type=${ptype_root}
EOF_SFDISK
    else
      exec_run sfdisk "$disk" <<EOF_SFDISK
label: dos
unit: MiB

1 : start=1, size=${boot_mib}, type=83, bootable
2 : size=${root_mib}, type=${ptype_root}
EOF_SFDISK
    fi
    PART_BOOT="$(exec_part_path "$disk" 1)"
    if [[ "${LVM_MODE}" == "none" ]]; then
      PART_ROOT="$(exec_part_path "$disk" 2)"
    else
      PART_PV="$(exec_part_path "$disk" 2)"
    fi
  fi

  exec_try sfdisk -d "$disk"
  return 0
}

exec_partition_wait_devices() {
  local disk="$1"
  local ok=1

  # Determine which partitions should exist and wait for them.
  if [[ "$BOOT_MODE" == "uefi" ]]; then
    exec_wait_for_part "$disk" 1 20 || ok=0
    exec_wait_for_part "$disk" 2 20 || ok=0
  elif [[ "$BOOT_MODE" == "biosgpt" ]]; then
    exec_wait_for_part "$disk" 1 20 || ok=0
    exec_wait_for_part "$disk" 2 20 || ok=0
  else
    # MBR: at least partition 1 must exist
    exec_wait_for_part "$disk" 1 20 || ok=0
  fi

  # swap/root/pv partitions depend on choices; just wait for what we set.
  [[ -z "$PART_SWAP" ]] || exec_wait_for_path "$PART_SWAP" 20 || ok=0
  [[ -z "$PART_ROOT" ]] || exec_wait_for_path "$PART_ROOT" 20 || ok=0
  [[ -z "$PART_PV"   ]] || exec_wait_for_path "$PART_PV"   20 || ok=0

  if (( ok == 0 )); then
    log "[!] partition: some partition nodes did not appear in time"
    ui_msg "Partition devices did not appear in time. See log: ${LOG_FILE}"
    return 1
  fi

  return 0
}
