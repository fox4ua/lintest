#!/usr/bin/env bash
# shellcheck shell=bash

# lib/exec/03-lvm.sh
#
# Creates LVM structures on PART_PV:
# - pvcreate on PART_PV
# - vgcreate (VG_NAME)
# - if LVM_MODE=thin: create thin-pool (THINPOOL_NAME)
# - create root LV
#
# Exports:
#   LV_ROOT          (e.g. /dev/pve/root)
#   LV_THINPOOL      (e.g. /dev/pve/thinpool) if thin
#
# Requires variables:
#   LVM_MODE: none|linear|thin
#   VG_NAME
#   THINPOOL_NAME (for thin, default: thinpool)
#   ROOT_SIZE_GIB (for thin virtual size is recommended >0)
#   PART_PV (device path like /dev/sdb3)

exec_lvm_create() {
  : "${LVM_MODE:?}"
  : "${VG_NAME:?}"
  : "${PART_PV:?}"

  LV_ROOT=""
  LV_THINPOOL=""

  if [[ "${LVM_MODE}" == "none" ]]; then
    log "[=] lvm: skipped (LVM_MODE=none)"
    return 0
  fi

  if [[ ! -b "${PART_PV}" ]]; then
    log "[!] lvm: PART_PV not found: ${PART_PV}"
    ui_msg "LVM: PV partition not found: ${PART_PV}\nSee log: ${LOG_FILE}"
    return 1
  fi

  exec_progress 0 "Preparing LVM tools..."
  exec_require_tools pvcreate vgcreate vgchange lvcreate pvs vgs lvs pvscan vgscan || return 1

  exec_progress 10 "Scanning for existing LVM metadata..."
  exec_try pvscan --cache
  exec_try vgscan --cache

  exec_progress 20 "Creating PV on ${PART_PV}..."
  # -ff/-y: overwrite any old signatures; safe because disk already selected/confirmed
  exec_run pvcreate -ff -y "${PART_PV}" || return 1

  exec_progress 40 "Creating/activating VG ${VG_NAME}..."
  if vgs --noheadings -o vg_name 2>/dev/null | awk '{$1=$1;print}' | grep -qx "${VG_NAME}"; then
    # VG exists: ensure our PV is inside it; otherwise extend
    if ! pvs --noheadings -o pv_name,vg_name 2>/dev/null | awk '{$1=$1;print}' | grep -q "^${PART_PV} ${VG_NAME}\$"; then
      exec_run vgextend "${VG_NAME}" "${PART_PV}" || return 1
    fi
  else
    exec_run vgcreate "${VG_NAME}" "${PART_PV}" || return 1
  fi

  exec_run vgchange -ay "${VG_NAME}" || return 1

  # THIN mode
  if [[ "${LVM_MODE}" == "thin" ]]; then
    local pool="${THINPOOL_NAME:-thinpool}"

    exec_progress 55 "Creating thin-pool ${VG_NAME}/${pool}..."
    # If pool exists — keep it
    if ! lvs --noheadings -o lv_name,vg_name 2>/dev/null | awk '{$1=$1;print}' | grep -q "^${pool} ${VG_NAME}\$"; then
      # Use most of free space for pool, keep small margin
      exec_run lvcreate -L 95%VG -T "${VG_NAME}/${pool}" || return 1
    fi

    LV_THINPOOL="/dev/${VG_NAME}/${pool}"
    exec_try lvchange -ay "${VG_NAME}/${pool}"

    exec_progress 70 "Creating thin LV root..."
    # For thin LV you SHOULD have explicit virtual size.
    if [[ "${ROOT_SIZE_GIB:-0}" -le 0 ]]; then
      log "[!] lvm(thin): ROOT_SIZE_GIB must be > 0 for thin volume"
      ui_msg "LVM thin mode requires ROOT_SIZE_GIB > 0 (virtual size).\nSet root size in UI.\nLog: ${LOG_FILE}"
      return 1
    fi

    if ! lvs --noheadings -o lv_name,vg_name 2>/dev/null | awk '{$1=$1;print}' | grep -q "^root ${VG_NAME}\$"; then
      exec_run lvcreate -V "${ROOT_SIZE_GIB}G" -T "${VG_NAME}/${pool}" -n root || return 1
    fi
  else
    # LINEAR mode
    exec_progress 70 "Creating linear LV root..."
    if ! lvs --noheadings -o lv_name,vg_name 2>/dev/null | awk '{$1=$1;print}' | grep -q "^root ${VG_NAME}\$"; then
      # root consumes all remaining extents in VG
      exec_run lvcreate -n root -l 100%FREE "${VG_NAME}" || return 1
    fi
  fi

  LV_ROOT="/dev/${VG_NAME}/root"

  exec_progress 85 "Activating LV root..."
  exec_try lvchange -ay "${VG_NAME}/root"

  exec_progress 92 "Waiting for device nodes..."
  exec_wait_for_path "${LV_ROOT}" 30 || {
    log "[!] lvm: LV root device not appeared: ${LV_ROOT}"
    exec_try ls -l "/dev/${VG_NAME}" || true
    exec_try lvs -a -o +devices "${VG_NAME}" || true
    ui_msg "LVM: root LV device did not appear: ${LV_ROOT}\nSee log: ${LOG_FILE}"
    return 1
  }

  export LV_ROOT LV_THINPOOL
  log "[=] lvm: OK VG=${VG_NAME} mode=${LVM_MODE} root=${LV_ROOT} pool=${LV_THINPOOL:-none}"

  exec_progress 100 "LVM created."
  return 0
}
