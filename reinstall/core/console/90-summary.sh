#!/usr/bin/env bash
set -Eeuo pipefail

ui_print_summary() {
  echo
  echo "================ SUMMARY ================"
  echo "DISK         : ${DISK}"


  echo "MIRROR       : ${DEBIAN_MIRROR}"

  echo "UI_MODE      : ${UI_MODE}"
  echo "BOOT_MODE    : ${BOOT_MODE}"
  echo "LVM_MODE     : ${LVM_MODE}"
  echo "BOOT_SIZE    : ${BOOT_SIZE}"
  echo "SWAP         : ${SWAP_CHOICE}"
  echo "ROOT_SIZE    : ${ROOT_SIZE}"
  if [[ -n "${ROOT_PASS}" ]]; then
    echo "ROOT_PASS    : ***set***"
  else
    echo "ROOT_PASS    : EMPTY (LOCK root)"
  fi
  echo "========================================"
  echo
}
