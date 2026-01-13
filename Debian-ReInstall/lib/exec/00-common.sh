#!/usr/bin/env bash
# shellcheck shell=bash

: "${LOG_FILE:?}"

exec_log_config() {
  log "[=] config: DISK=${DISK} BOOT_MODE=${BOOT_MODE} LVM_MODE=${LVM_MODE} VG=${VG_NAME} THINPOOL=${THINPOOL_NAME}"
  log "[=] config: /boot=${BOOT_SIZE_MIB}MiB swap=${SWAP_SIZE_GIB}GiB root=${ROOT_SIZE_GIB}GiB efi=${EFI_SIZE_MIB}MiB"
  log "[=] config: debian=${DEBIAN_VERSION} suite=${DEBIAN_SUITE} mirror=${DEBIAN_MIRROR}"
  log "[=] config: net_stack=${NET_STACK} iface=${NET_IFACE} v4=${NET4_ENABLE}/${NET4_MODE} v6=${NET6_ENABLE}/${NET6_MODE}"
  log "[=] config: hostname=${HOSTNAME_SHORT} domain=${HOSTS_DOMAIN} fqdn=${HOSTS_FQDN}"
}

exec_require_tools() {
  local missing=0
  local t
  for t in "$@"; do
    if ! command -v "$t" >/dev/null 2>&1; then
      log "[!] missing tool: $t"
      missing=1
    fi
  done

  if (( missing )); then
    ui_msg "Missing required tools. See log: ${LOG_FILE}"
    return 1
  fi

  return 0
}

exec_run() {
  # Log command line as it will be executed.
  log "[>] $*"
  "$@"
}

exec_try() {
  # Best-effort command. Non-zero rc is logged but not fatal.
  local rc
  log "[>] $*"
  "$@" || rc=$?
  rc=${rc:-0}
  if (( rc != 0 )); then
    log "[!] command failed rc=${rc}: $*"
  fi
  return 0
}
