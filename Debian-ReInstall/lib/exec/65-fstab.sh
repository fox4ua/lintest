#!/usr/bin/env bash
# shellcheck shell=bash

# Writes /etc/fstab by UUID.
# Requires:
#   LVM_MODE, PART_ROOT (if none) OR LV_ROOT (/dev/VG/root)
#   PART_BOOT, PART_EFI, PART_SWAP optional
#   TARGET_DIR, LOG_FILE

exec_fstab_write() {
  : "${TARGET_DIR:?}"
  : "${LOG_FILE:?}"
  : "${LVM_MODE:?}"

  exec_require_tools blkid mkdir cat || return 1

  local root_dev=""
  if [[ "${LVM_MODE}" == "none" ]]; then
    : "${PART_ROOT:?PART_ROOT is required when LVM_MODE=none}"
    root_dev="${PART_ROOT}"
  else
    root_dev="${LV_ROOT:-/dev/${VG_NAME}/root}"
  fi

  if [[ ! -b "${root_dev}" ]]; then
    ui_msg "Root device not found: ${root_dev}\nLog: ${LOG_FILE}"
    return 1
  fi

  exec_progress 0 "Detecting UUIDs..."

  local uuid_root uuid_boot uuid_efi uuid_swap
  uuid_root="$(blkid -s UUID -o value "${root_dev}" 2>/dev/null || true)"
  [[ -n "${uuid_root}" ]] || { ui_msg "Cannot get UUID for root: ${root_dev}\nLog: ${LOG_FILE}"; return 1; }

  if [[ -n "${PART_BOOT:-}" ]]; then
    uuid_boot="$(blkid -s UUID -o value "${PART_BOOT}" 2>/dev/null || true)"
    [[ -n "${uuid_boot}" ]] || { ui_msg "Cannot get UUID for /boot: ${PART_BOOT}\nLog: ${LOG_FILE}"; return 1; }
  fi

  if [[ -n "${PART_EFI:-}" ]]; then
    uuid_efi="$(blkid -s UUID -o value "${PART_EFI}" 2>/dev/null || true)"
    [[ -n "${uuid_efi}" ]] || { ui_msg "Cannot get UUID for EFI: ${PART_EFI}\nLog: ${LOG_FILE}"; return 1; }
  fi

  if [[ -n "${PART_SWAP:-}" ]]; then
    uuid_swap="$(blkid -s UUID -o value "${PART_SWAP}" 2>/dev/null || true)"
    [[ -n "${uuid_swap}" ]] || { ui_msg "Cannot get UUID for swap: ${PART_SWAP}\nLog: ${LOG_FILE}"; return 1; }
  fi

  exec_progress 60 "Writing /etc/fstab..."
  mkdir -p "${TARGET_DIR}/etc" || true

  cat >"${TARGET_DIR}/etc/fstab" <<EOF
# /etc/fstab: static file system information.
proc /proc proc defaults 0 0
UUID=${uuid_root} / ext4 defaults,errors=remount-ro 0 1
EOF

  if [[ -n "${uuid_boot:-}" ]]; then
    echo "UUID=${uuid_boot} /boot ext4 defaults 0 2" >>"${TARGET_DIR}/etc/fstab"
  fi

  if [[ -n "${uuid_efi:-}" ]]; then
    echo "UUID=${uuid_efi} /boot/efi vfat umask=0077 0 1" >>"${TARGET_DIR}/etc/fstab"
  fi

  if [[ -n "${uuid_swap:-}" ]]; then
    echo "UUID=${uuid_swap} none swap sw 0 0" >>"${TARGET_DIR}/etc/fstab"
  fi

  exec_progress 100 "fstab written."
  return 0
}
