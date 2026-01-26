#!/usr/bin/env bash
set -Eeuo pipefail

ui_print_summary() {
  format_gib_summary() {
    local gib="${1:-0}"
    if [[ -z "$gib" || ! "$gib" =~ ^[0-9]+$ ]]; then
      printf '%s' "$gib"
      return
    fi
    printf '%s GiB' "$gib"
  }

  format_mib_summary() {
    local mib="${1:-0}"
    if [[ -z "$mib" || ! "$mib" =~ ^[0-9]+$ ]]; then
      printf '%s' "$mib"
      return
    fi
    if (( mib % 1024 == 0 )); then
      printf '%s GiB' $(( mib / 1024 ))
    else
      printf '%s MiB' "$mib"
    fi
  }

  echo
  echo "================ SUMMARY ================"
  echo "DISK              : ${DISK}"
  echo "BOOT_MODE         : ${BOOT_MODE}"
  echo "LVM_MODE          : ${LVM_MODE}"
  if [[ "${LVM_MODE}" == "lvm" || "${LVM_MODE}" == "thin" ]]; then
    echo "VG_NAME           : ${VG_NAME}"
  fi
  if [[ "${LVM_MODE}" == "thin" ]]; then
    echo "THINPOOL_NAME     : ${THINPOOL_NAME}"
    echo "THINPOOL_PERCENT  : ${THINPOOL_PERCENT}"
  fi
  echo "BOOT_SIZE         : $(format_mib_summary "$BOOT_SIZE")"

  if [[ "$SWAP_SIZE" == "0" || -z "$SWAP_SIZE" ]]; then
    swap_summary="none"
  else
    swap_summary="$(format_mib_summary "$SWAP_SIZE")"
  fi
  echo "SWAP_SIZE         : ${swap_summary}"
  echo "ROOT_FS           : ${ROOT_FS}"
  echo "ROOT_SIZE         : $(format_gib_summary "$ROOT_SIZE")"
  if [[ -n "${DATA_FS}" ]]; then
    echo "DATA_FS           : ${DATA_FS}"
  else
    echo "DATA_FS           : (none)"
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
