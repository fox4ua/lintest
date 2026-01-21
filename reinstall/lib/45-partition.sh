#!/usr/bin/env bash
# shellcheck shell=bash

# Partitioning + resolving device paths.
#
# Depends on variables set by install.sh:
#   DISK, BOOT_MODE, EFI_SIZE, BOOT_SIZE, ROOT_SIZE
#   LVM_MODE, HAS_SWAP, SWAP_SIZE
#
# Requires functions:
#   log(), die() (lib/00-log.sh)
#   kernel_reread_pt(), resolve_part_by_label(), list_disk_parts() (lib/06-disk.sh)
#
# Outputs (globals):
#   IS_LVM (0/1)
#   P1, P_BOOT, P_SWAP, P_ROOT, P_DATA, P_PV

partition_create_gpt() {
  log "Creating GPT partitions..."

  IS_LVM=0
  [[ "${LVM_MODE:-none}" != "none" ]] && IS_LVM=1

  local expected_parts=0
  if [[ "$IS_LVM" == "1" ]]; then
    expected_parts=3   # p1 + p2 + pv
  else
    expected_parts=$(( 3 + ${HAS_SWAP:-0} ))  # p1 + p2 + root + swap?
    expected_parts=$(( expected_parts + 1 )) # add DATA
  fi

  if [[ "${BOOT_MODE:-auto}" == "uefi" ]]; then
    if [[ "$IS_LVM" == "1" ]]; then
      sgdisk \
        -n1:1MiB:+${EFI_SIZE}   -t1:EF00 -c1:"EFI" \
        -n2:0:+${BOOT_SIZE}     -t2:8300 -c2:"BOOT" \
        -n3:0:0                 -t3:8E00 -c3:"PV" \
        "$DISK"
    else
      if [[ "${HAS_SWAP:-0}" == "1" ]]; then
        sgdisk \
          -n1:1MiB:+${EFI_SIZE} -t1:EF00 -c1:"EFI" \
          -n2:0:+${BOOT_SIZE}   -t2:8300 -c2:"BOOT" \
          -n3:0:+${SWAP_SIZE}   -t3:8200 -c3:"SWAP" \
          -n4:0:+${ROOT_SIZE}   -t4:8300 -c4:"ROOT" \
          -n5:0:0               -t5:8300 -c5:"DATA" \
          "$DISK"
      else
        sgdisk \
          -n1:1MiB:+${EFI_SIZE} -t1:EF00 -c1:"EFI" \
          -n2:0:+${BOOT_SIZE}   -t2:8300 -c2:"BOOT" \
          -n3:0:+${ROOT_SIZE}   -t3:8300 -c3:"ROOT" \
          -n4:0:0               -t4:8300 -c4:"DATA" \
          "$DISK"
      fi
    fi
  else
    # BIOS
    if [[ "$IS_LVM" == "1" ]]; then
      sgdisk \
        -n1:1MiB:+1MiB          -t1:EF02 -c1:"BIOSBOOT" \
        -n2:0:+${BOOT_SIZE}     -t2:8300 -c2:"BOOT" \
        -n3:0:0                 -t3:8E00 -c3:"PV" \
        "$DISK"
    else
      if [[ "${HAS_SWAP:-0}" == "1" ]]; then
        sgdisk \
          -n1:1MiB:+1MiB        -t1:EF02 -c1:"BIOSBOOT" \
          -n2:0:+${BOOT_SIZE}   -t2:8300 -c2:"BOOT" \
          -n3:0:+${SWAP_SIZE}   -t3:8200 -c3:"SWAP" \
          -n4:0:+${ROOT_SIZE}   -t4:8300 -c4:"ROOT" \
          -n5:0:0               -t5:8300 -c5:"DATA" \
          "$DISK"
      else
        sgdisk \
          -n1:1MiB:+1MiB        -t1:EF02 -c1:"BIOSBOOT" \
          -n2:0:+${BOOT_SIZE}   -t2:8300 -c2:"BOOT" \
          -n3:0:+${ROOT_SIZE}   -t3:8300 -c3:"ROOT" \
          -n4:0:0               -t4:8300 -c4:"DATA" \
          "$DISK"
      fi
    fi
  fi

  kernel_reread_pt "$DISK" "$expected_parts" || true
}

partition_resolve_devices() {
  # Resolve by labels first
  P1=""
  P_BOOT="$(resolve_part_by_label BOOT)"
  P_SWAP=""
  P_ROOT=""
  P_DATA=""
  P_PV=""

  if [[ "${BOOT_MODE}" == "uefi" ]]; then
    P1="$(resolve_part_by_label EFI)"
  else
    P1="$(resolve_part_by_label BIOSBOOT)"
  fi

  if [[ "${HAS_SWAP:-0}" == "1" && "${IS_LVM:-0}" == "0" ]]; then
    P_SWAP="$(resolve_part_by_label SWAP)"
  fi

  if [[ "${IS_LVM:-0}" == "1" ]]; then
    P_PV="$(resolve_part_by_label PV)"
  else
    P_ROOT="$(resolve_part_by_label ROOT)"
    P_DATA="$(resolve_part_by_label DATA)"
  fi

  if [[ -z "$P_BOOT" || ( "${BOOT_MODE}" == "uefi" && -z "$P1" ) || ( "${BOOT_MODE}" == "bios" && -z "$P1" ) ]]; then
    log "WARN: PARTLABEL resolve incomplete; using lsblk fallback order..."
  fi

  # Fallback mapping by order
  mapfile -t _parts < <(list_disk_parts "$DISK")
  if [[ "${IS_LVM:-0}" == "1" ]]; then
    [[ "${#_parts[@]}" -ge 3 ]] || die "Cannot map partitions (expected >=3)"
    P1="${P1:-${_parts[0]}}"
    P_BOOT="${P_BOOT:-${_parts[1]}}"
    P_PV="${P_PV:-${_parts[2]}}"
  else
    if [[ "${HAS_SWAP:-0}" == "1" ]]; then
      [[ "${#_parts[@]}" -ge 5 ]] || die "Cannot map partitions (expected >=5)"
      P1="${P1:-${_parts[0]}}"
      P_BOOT="${P_BOOT:-${_parts[1]}}"
      P_SWAP="${P_SWAP:-${_parts[2]}}"
      P_ROOT="${P_ROOT:-${_parts[3]}}"
      P_DATA="${P_DATA:-${_parts[4]}}"
    else
      [[ "${#_parts[@]}" -ge 4 ]] || die "Cannot map partitions (expected >=4)"
      P1="${P1:-${_parts[0]}}"
      P_BOOT="${P_BOOT:-${_parts[1]}}"
      P_ROOT="${P_ROOT:-${_parts[2]}}"
      P_DATA="${P_DATA:-${_parts[3]}}"
    fi
  fi

  # Sanity
  [[ -b "$P_BOOT" ]] || die "BOOT partition not found"
  if [[ "${BOOT_MODE}" == "uefi" ]]; then [[ -b "$P1" ]] || die "EFI partition not found"; fi
  if [[ "${BOOT_MODE}" == "bios" ]]; then [[ -b "$P1" ]] || die "BIOSBOOT partition not found"; fi

  if [[ "${IS_LVM:-0}" == "1" ]]; then
    [[ -b "$P_PV" ]] || die "PV partition not found"
  else
    [[ -b "$P_ROOT" && -b "$P_DATA" ]] || die "ROOT/DATA partitions not found"
    if [[ "${HAS_SWAP:-0}" == "1" ]]; then [[ -b "$P_SWAP" ]] || die "SWAP partition not found"; fi
  fi
}
