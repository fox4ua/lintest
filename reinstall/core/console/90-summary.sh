#!/usr/bin/env bash
set -Eeuo pipefail

ui_print_summary() {
  echo
  echo "================ SUMMARY ================"
  echo "DISK         : ${DISK}"
  echo "BOOT_MODE    : ${BOOT_MODE}"
  echo "LVM_MODE     : ${LVM_MODE}"
  if [[ "${LVM_MODE}" == "lvm" || "${LVM_MODE}" == "thin" ]]; then
    echo "VG_NAME      : ${VG_NAME}"
  fi
  if [[ "${LVM_MODE}" == "thin" ]]; then
    echo "THINPOOL_NAME      : ${THINPOOL_NAME}"
    echo "THINPOOL_PERCENT   : ${THINPOOL_PERCENT}"
  fi
  echo "BOOT_SIZE    : ${BOOT_SIZE}"
  echo "SWAP         : ${SWAP_CHOICE}"
  echo "ROOT_FS      : ${ROOT_SIZE}"
  echo "ROOT_SIZE    : ${ROOT_SIZE}"


  echo "MIRROR       : ${DEBIAN_MIRROR}"


  if [[ -n "${ROOT_PASS}" ]]; then
    echo "ROOT_PASS    : ***set***"
  else
    echo "ROOT_PASS    : EMPTY (LOCK root)"
  fi
  echo "========================================"
  echo
}
