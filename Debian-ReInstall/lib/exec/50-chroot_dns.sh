#!/usr/bin/env bash
# shellcheck shell=bash

# Chroot DNS:
# Writes ${TARGET_DIR}/etc/resolv.conf as plain file (not symlink).

exec_chroot_dns_apply() {
  : "${TARGET_DIR:?TARGET_DIR is required}"
  : "${LOG_FILE:?LOG_FILE is required}"
  : "${CHROOT_DNS_FORCE_FALLBACK:=0}"
  : "${CHROOT_DNS_FALLBACK_SERVERS:=1.1.1.1 8.8.8.8}"

  exec_require_tools cp chmod chown grep cat rm mkdir || return 1

  local target_rc="${TARGET_DIR}/etc/resolv.conf"
  mkdir -p "${TARGET_DIR}/etc" || true

  # Replace symlink with plain file (common with systemd-resolved)
  if [[ -L "$target_rc" ]]; then
    exec_try rm -f "$target_rc"
  fi

  if (( CHROOT_DNS_FORCE_FALLBACK == 1 )); then
    log "[!] chroot_dns: forcing fallback nameservers"
    printf 'nameserver %s\n' ${CHROOT_DNS_FALLBACK_SERVERS} >"$target_rc"
  elif [[ -s /etc/resolv.conf ]] && grep -qE '^\s*nameserver\s+' /etc/resolv.conf; then
    exec_try cp -f /etc/resolv.conf "$target_rc"
    log "[=] chroot_dns: copied host resolv.conf"


    local has_public=0
    local ns
    while read -r _ ns _; do
      [[ -z "$ns" ]] && continue
      if [[ "$ns" == 127.* || "$ns" == "::1" || "$ns" == "0.0.0.0" ]]; then
        continue
      fi
      has_public=1
      break
    done < <(grep -E '^\s*nameserver\s+' "$target_rc" || true)

    if (( has_public == 0 )); then
      log "[!] chroot_dns: resolv.conf has only localhost nameservers; using fallback"
      printf 'nameserver %s\n' ${CHROOT_DNS_FALLBACK_SERVERS} >"$target_rc"
    fi
  else
    log "[!] chroot_dns: host resolv.conf has no nameserver; using fallback"
    printf 'nameserver %s\n' ${CHROOT_DNS_FALLBACK_SERVERS} >"$target_rc"
  fi

  exec_try chmod 644 "$target_rc"
  exec_try chown root:root "$target_rc"
  return 0
}
