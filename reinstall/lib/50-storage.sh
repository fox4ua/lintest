#!/usr/bin/env bash
# shellcheck shell=bash

# Storage setup: format boot/efi, create LVM/thin devices, format root/data, prepare swap.
#
# Inputs (globals):
#   BOOT_MODE, LVM_MODE, IS_LVM, HAS_SWAP
#   P_BOOT, P1, P_SWAP, P_ROOT, P_DATA, P_PV
#   ROOT_SIZE, SWAP_SIZE
#   VG_NAME, LV_ROOT_NAME, LV_SWAP_NAME, LV_DATA_NAME
#   THINPOOL_NAME, THINPOOL_PCT_FREE
#   ROOT_FS, DATA_FS
#   DISK
#
# Requires:
#   log(), die()                 (lib/00-log.sh)
#   need_cmd()                   (lib/01-utils.sh)
#   have_cmd()                   (lib/01-utils.sh)
#   release_disk()               (lib/06-disk.sh)

# Outputs (globals):
#   ROOT_DEV, DATA_DEV, SWAP_DEV (SWAP_DEV may be empty)

storage_format_boot_efi() {
  log "Formatting /boot..."
  mkfs.ext4 -F -L boot "$P_BOOT"

  if [[ "$BOOT_MODE" == "uefi" ]]; then
    need_cmd mkfs.vfat
    log "Formatting EFI..."
    mkfs.vfat -F32 -n EFI "$P1"
  fi
}

storage_format_swap_partition_if_needed() {
  if [[ "${IS_LVM:-0}" == "0" && "${HAS_SWAP:-0}" == "1" ]]; then
    need_cmd mkswap
    log "Creating swap (partition)..."
    mkswap -L swap "$P_SWAP"
  fi
}

storage_prepare_devices() {
  ROOT_DEV=""
  DATA_DEV=""
  SWAP_DEV=""

  if [[ "${IS_LVM:-0}" == "0" ]]; then
    ROOT_DEV="$P_ROOT"
    DATA_DEV="$P_DATA"
    if [[ "${HAS_SWAP:-0}" == "1" ]]; then
      SWAP_DEV="$P_SWAP"
    fi
    return 0
  fi

  # LVM modes
  log "Creating LVM PV/VG on $P_PV..."
  release_disk "$DISK"
  wipefs -a "$P_PV" || true

  pvcreate -ff -y -Z y "$P_PV"
  vgcreate "$VG_NAME" "$P_PV"

  log "Creating root LV: ${VG_NAME}/${LV_ROOT_NAME} size=$ROOT_SIZE (linear)"
  lvcreate -n "$LV_ROOT_NAME" -L "$ROOT_SIZE" "$VG_NAME"
  ROOT_DEV="/dev/${VG_NAME}/${LV_ROOT_NAME}"

  if [[ "${HAS_SWAP:-0}" == "1" ]]; then
    log "Creating swap LV: ${VG_NAME}/${LV_SWAP_NAME} size=$SWAP_SIZE (linear)"
    lvcreate -n "$LV_SWAP_NAME" -L "$SWAP_SIZE" "$VG_NAME"
    SWAP_DEV="/dev/${VG_NAME}/${LV_SWAP_NAME}"
  fi

  if [[ "$LVM_MODE" == "lvm" ]]; then
    log "Creating data LV: ${VG_NAME}/${LV_DATA_NAME} = 100%FREE (linear)"
    lvcreate -n "$LV_DATA_NAME" -l 100%FREE "$VG_NAME"
    DATA_DEV="/dev/${VG_NAME}/${LV_DATA_NAME}"
    return 0
  fi

  # thin: thinpool ~= THINPOOL_PCT_FREE%FREE, data is thin LV inside
  log "Creating thinpool: ${VG_NAME}/${THINPOOL_NAME} = ${THINPOOL_PCT_FREE}%FREE"
  lvcreate --type thin-pool -n "$THINPOOL_NAME" -l "${THINPOOL_PCT_FREE}%FREE" "$VG_NAME"

  local pool_bytes reserve data_vbytes
  pool_bytes="$(
    LC_ALL=C lvs --noheadings --units B --nosuffix -o LV_SIZE "${VG_NAME}/${THINPOOL_NAME}" \
      | head -n1 \
      | awk '{gsub(/^[ \t]+|[ \t]+$/,""); printf "%.0f\n",$1}'
  )"
  [[ "$pool_bytes" =~ ^[0-9]+$ ]] || die "Cannot parse thinpool size (pool_bytes='$pool_bytes')"

  # Data vsize: almost all pool (leave 128MiB to avoid rounding edge cases)
  reserve=$((128*1024*1024))
  if (( pool_bytes > reserve )); then
    data_vbytes=$(( pool_bytes - reserve ))
  else
    data_vbytes=$pool_bytes
  fi

  log "Creating thin data LV inside thinpool: ${VG_NAME}/${LV_DATA_NAME} vsize=${data_vbytes}B"
  lvcreate -V "${data_vbytes}B" -T "${VG_NAME}/${THINPOOL_NAME}" -n "$LV_DATA_NAME"
  DATA_DEV="/dev/${VG_NAME}/${LV_DATA_NAME}"
}

storage_format_root_data_and_swap() {
  log "Formatting root ($ROOT_FS) on $ROOT_DEV..."
  case "$ROOT_FS" in
    ext4)  mkfs.ext4 -F -L root "$ROOT_DEV" ;;
    xfs)   mkfs.xfs -f -L root "$ROOT_DEV" ;;
    btrfs) mkfs.btrfs -f -L root "$ROOT_DEV" ;;
    *) die "Unsupported ROOT_FS: $ROOT_FS" ;;
  esac

  log "Formatting data ($DATA_FS) on $DATA_DEV..."
  case "$DATA_FS" in
    ext4)  mkfs.ext4 -F -L data "$DATA_DEV" ;;
    xfs)   mkfs.xfs -f -L data "$DATA_DEV" ;;
    btrfs) mkfs.btrfs -f -L data "$DATA_DEV" ;;
    *) die "Unsupported DATA_FS: $DATA_FS" ;;
  esac

  if [[ "${IS_LVM:-0}" == "1" && "${HAS_SWAP:-0}" == "1" ]]; then
    need_cmd mkswap
    log "Creating swap (LV)..."
    mkswap -L swap "$SWAP_DEV"
  fi
}
