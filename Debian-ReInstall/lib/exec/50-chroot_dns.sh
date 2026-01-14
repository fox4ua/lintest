#!/usr/bin/env bash
# shellcheck shell=bash

# Chroot DNS:
# Writes ${TARGET_DIR}/etc/resolv.conf as plain file (not symlink).

exec_chroot_dns_apply() {
  : "${TARGET_DIR:?TARGET_DIR is required}"
  : "${LOG_FILE:?LOG_FILE is required}"

  exec_require_tools cp chmod chown grep cat rm mkdir || return 1

  local target_rc="${TARGET_DIR}/etc/resolv.conf"
  mkdir -p "${TARGET_DIR}/etc" || true

  # Replace symlink with plain file (common with systemd-resolved)
  if [[ -L "$target_rc" ]]; then
    exec_try rm -f "$target_rc"
  fi

  if [[ -s /etc/resolv.conf ]] && grep -qE '^\s*nameserver\s+' /etc/resolv.conf; then
    exec_try cp -f /etc/resolv.conf "$target_rc"
    log "[=] chroot_dns: copied host resolv.conf"
  else
    log "[!] chroot_dns: host resolv.conf has no nameserver; using fallback"
    cat >"$target_rc" <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
  fi

  exec_try chmod 644 "$target_rc"
  exec_try chown root:root "$target_rc"
  return 0
}
