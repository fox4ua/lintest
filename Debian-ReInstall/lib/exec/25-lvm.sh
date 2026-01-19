#!/usr/bin/env bash
# shellcheck shell=bash

exec_lvm_create() {
  : "${LVM_MODE:?}"
  : "${VG_NAME:?}"
  : "${PART_PV:?}"
  : "${DISK:?}"

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
  exec_require_tools pvcreate vgcreate vgchange lvcreate pvs vgs lvs pvscan vgscan dmsetup || return 1

  exec_progress 10 "Ensuring PV is free (deactivate + dm cleanup + wipefs)..."
  exec_lvm_force_free_pv "${DISK}" "${PART_PV}" || return 1

  exec_progress 20 "Creating PV on ${PART_PV}..."
  # overwrite old signatures (if any)
  if ! exec_run pvcreate -ff -y "${PART_PV}"; then
    exec_lvm_dump_busy_state "${DISK}" "${PART_PV}"
    ui_msg "pvcreate failed on ${PART_PV}.\nMost likely the device is still busy.\nSee log: ${LOG_FILE}"
    return 1
  fi

  exec_progress 40 "Creating VG ${VG_NAME}..."
  # Always create fresh VG on this PV (avoid reusing stale cached VG metadata).
  # If VG_NAME exists but is NOT on this disk -> refuse (safety).
  if vgs --noheadings -o vg_name 2>/dev/null | awk '{$1=$1;print}' | grep -qx "${VG_NAME}"; then
    if ! pvs --noheadings -o pv_name,vg_name 2>/dev/null | awk '{$1=$1;print}' | grep -q "^${DISK}.* ${VG_NAME}\$"; then
      log "[!] lvm: VG ${VG_NAME} exists on another disk; refusing to reuse"
      ui_msg "VG ${VG_NAME} already exists (not on selected disk).\nChoose another VG name.\nLog: ${LOG_FILE}"
      return 1
    fi
    # VG exists on this disk (stale) -> make sure it's inactive and remove LVs (best-effort), then vgremove.
    exec_try vgchange -an "${VG_NAME}"
    exec_try lvremove -fy "${VG_NAME}" >/dev/null 2>&1 || true
    exec_try vgremove -fy "${VG_NAME}" >/dev/null 2>&1 || true
  fi

  exec_run vgcreate "${VG_NAME}" "${PART_PV}" || return 1
  exec_run vgchange -ay "${VG_NAME}" || return 1

  if [[ "${LVM_MODE}" == "thin" ]]; then
    local pool="${THINPOOL_NAME:-thinpool}"

    exec_progress 55 "Creating thin-pool ${VG_NAME}/${pool}..."
    if ! lvs --noheadings -o lv_name,vg_name 2>/dev/null | awk '{$1=$1;print}' | grep -q "^${pool} ${VG_NAME}\$"; then
      exec_run lvcreate --yes --wipesignatures y -l 95%VG -T "${VG_NAME}/${pool}" || return 1
    fi

    LV_THINPOOL="/dev/${VG_NAME}/${pool}"
    exec_try lvchange -ay "${VG_NAME}/${pool}"

    exec_progress 70 "Creating thin LV root..."
    if [[ "${ROOT_SIZE_GIB:-0}" -le 0 ]]; then
      ui_msg "LVM thin mode requires ROOT_SIZE_GIB > 0.\nSet root size in UI.\nLog: ${LOG_FILE}"
      return 1
    fi

    if ! lvs --noheadings -o lv_name,vg_name 2>/dev/null | awk '{$1=$1;print}' | grep -q "^root ${VG_NAME}\$"; then
      exec_run lvcreate --yes --wipesignatures y -V "${ROOT_SIZE_GIB}G" -T "${VG_NAME}/${pool}" -n root || return 1
    fi
  else
    exec_progress 70 "Creating linear LV root..."
    if ! lvs --noheadings -o lv_name,vg_name 2>/dev/null | awk '{$1=$1;print}' | grep -q "^root ${VG_NAME}\$"; then
      exec_run lvcreate --yes --wipesignatures y -n root -l 100%FREE "${VG_NAME}" || return 1
    fi
  fi

  LV_ROOT="/dev/${VG_NAME}/root"

  exec_progress 85 "Activating LV root..."
  exec_try lvchange -ay "${VG_NAME}/root"

  exec_progress 92 "Waiting for device nodes..."
  exec_wait_for_path "${LV_ROOT}" 60 || {
    log "[!] lvm: LV root device not appeared: ${LV_ROOT}"
    exec_lvm_dump_busy_state "${DISK}" "${PART_PV}"
    ui_msg "LVM: root LV device did not appear: ${LV_ROOT}\nSee log: ${LOG_FILE}"
    return 1
  }

  export LV_ROOT LV_THINPOOL
  log "[=] lvm: OK VG=${VG_NAME} mode=${LVM_MODE} root=${LV_ROOT} pool=${LV_THINPOOL:-none}"

  exec_progress 100 "LVM created."
  return 0
}

exec_lvm_force_free_pv() {
  local disk="$1"
  local pv="$2"
  local -a vgs_on_disk=()

  # 1) deactivate any VG that uses PVs on this disk
  mapfile -t vgs_on_disk < <(
    pvs --noheadings -o vg_name,pv_name 2>/dev/null \
      | awk -v d="$disk" '$2 ~ "^"d {print $1}' \
      | sort -u
  )
  if (( ${#vgs_on_disk[@]} )); then
    exec_try vgchange -an "${vgs_on_disk[@]}" >/dev/null 2>&1 || true
  fi

  # 2) remove dm devices depending on this disk (prevents "Device or resource busy")
  exec_lvm_dm_remove_by_disk "$disk"

  # 3) wipe signatures on PV partition itself
  exec_try wipefs -a "$pv"

  # 4) settle udev
  exec_try udevadm settle

  return 0
}

exec_lvm_dm_remove_by_disk() {
  local disk="$1"
  command -v dmsetup >/dev/null 2>&1 || return 0

  local base
  base="$(basename "$disk")"

  local name deps
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    deps="$(dmsetup deps -o devname "$name" 2>/dev/null || true)"
    if grep -q "${base}" <<<"$deps"; then
      log "[>] dmsetup remove -f ${name} (deps: ${deps//$'\n'/ })"
      dmsetup remove -f "$name" >/dev/null 2>&1 || log "[!] dmsetup remove failed: ${name}"
    fi
  done < <(dmsetup ls --noheadings -o name 2>/dev/null || true)

  return 0
}

exec_lvm_dump_busy_state() {
  local disk="$1"
  local pv="$2"

  log "[=] debug: lsblk -f ${disk}"
  exec_try lsblk -f "$disk" || true

  log "[=] debug: lsblk -f ${pv}"
  exec_try lsblk -f "$pv" || true

  if command -v dmsetup >/dev/null 2>&1; then
    log "[=] debug: dmsetup ls --tree"
    exec_try dmsetup ls --tree || true
  fi

  if command -v fuser >/dev/null 2>&1; then
    log "[=] debug: fuser -vm ${pv}"
    exec_try fuser -vm "$pv" || true
  fi
}
