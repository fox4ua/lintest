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
  echo "BOOT_SIZE       : ${BOOT_SIZE}"
  local swap_summary="${SWAP_SIZE:-${SWAP_CHOICE:-}}"
  if [[ "$swap_summary" == "0" || -z "$swap_summary" ]]; then
    swap_summary="none"
  fi
  echo "SWAP            : ${swap_summary}"
  echo "ROOT_FS         : ${ROOT_FS}"
  echo "ROOT_SIZE       : ${ROOT_SIZE}"


  if [[ -n "${DATA_FS}" ]]; then
    echo "DATA_FS         : ${DATA_FS}"
  else
    echo "DATA_FS         : (none)"
  fi


  echo "DEBIAN_MAJOR : ${DEBIAN_MAJOR}"
  echo "DEBIAN_REL   : ${DEBIAN_CODENAME}"
  echo "MIRROR       : ${DEBIAN_MIRROR}"
  echo "HOSTNAME     : ${HOSTNAME}"
  if [[ -n "${HOSTS_FQDN}" ]]; then
    echo "HOSTS_FQDN   : ${HOSTS_FQDN}"
  fi

  if [[ -n "${ROOT_PASS}" ]]; then
    echo "ROOT_PASS    : ***set***"
  else
    echo "ROOT_PASS    : EMPTY (LOCK root)"
  fi
  echo "========================================"
  echo
}
