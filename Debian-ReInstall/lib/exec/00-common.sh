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

# Close all inherited FDs >=3 for a child process.
exec__close_extra_fds() {
  local fd path
  shopt -s nullglob
  for path in /proc/$$/fd/*; do
    fd="${path##*/}"
    [[ "$fd" =~ ^[0-9]+$ ]] || continue
    (( fd >= 3 )) || continue
    eval "exec ${fd}>&-" 2>/dev/null || true
  done
  shopt -u nullglob
}

exec_run() {
  log "[>] $*"
  (
    exec__close_extra_fds
    "$@" >>"$LOG_FILE" 2>&1
  ) || {
    local rc=$?
    log "[!] command failed rc=${rc}: $*"
    return $rc
  }
  return 0
}

exec_try() {
  local rc
  log "[>] $*"
  (
    exec__close_extra_fds
    "$@" >>"$LOG_FILE" 2>&1
  ) || rc=$?
  rc=${rc:-0}
  if (( rc != 0 )); then
    log "[!] command failed rc=${rc}: $*"
  fi
  return 0
}

