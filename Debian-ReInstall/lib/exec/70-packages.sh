#!/usr/bin/env bash

chroot_apt_update() {
  local output
  output="$(mktemp -t apt-update.XXXXXX)"
  log "[chroot] apt-get update"
  chroot "$TARGET_DIR" /usr/bin/env -i \
    HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    DEBIAN_FRONTEND=noninteractive \
    bash -lc "apt-get update -o Acquire::Retries=3" >"$output" 2>&1
  local rc=$?
  cat "$output" >>"$LOG_FILE"
  if grep -Eq 'Temporary failure resolving|Failed to fetch|Could not resolve|No address associated with hostname' "$output"; then
    rc=1
  fi
  rm -f "$output"
  return $rc
}

prepare_install_resolv_conf() {
  if [[ -n "${NET4_DNS:-}" || -n "${NET6_DNS:-}" ]]; then
    write_resolv_conf_fallback
  else
    write_host_resolv_conf
  fi
  ensure_target_nsswitch_dns
}


ensure_chroot_dns() {
  if [[ -f "$TARGET_DIR/etc/resolv.conf" ]]; then
    ensure_target_nsswitch_dns
    if chroot_run_quiet "getent hosts deb.debian.org >/dev/null" \
      && chroot_run_quiet "getent hosts security.debian.org >/dev/null"; then
      return 0
    fi
  fi

  prepare_install_resolv_conf

  if chroot_run_quiet "getent hosts deb.debian.org >/dev/null" \
    && chroot_run_quiet "getent hosts security.debian.org >/dev/null"; then
    return 0
  fi

  log "[!] chroot DNS failed; trying fallback resolv.conf"
  write_resolv_conf_defaults
  ensure_target_nsswitch_dns
  if chroot_run_quiet "getent hosts deb.debian.org >/dev/null" \
    && chroot_run_quiet "getent hosts security.debian.org >/dev/null"; then
    return 0
  fi

  log "[!] fallback DNS failed; trying public resolvers"
  write_resolv_conf_public
  ensure_target_nsswitch_dns
  if chroot_run_quiet "getent hosts deb.debian.org >/dev/null" \
    && chroot_run_quiet "getent hosts security.debian.org >/dev/null"; then
    return 0
  fi

  log "[!] public resolvers failed; restoring host resolv.conf"
  write_target_resolv_conf_from_host
  ensure_target_nsswitch_dns
  if chroot_run_quiet "getent hosts deb.debian.org >/dev/null" \
    && chroot_run_quiet "getent hosts security.debian.org >/dev/null"; then
    return 0
  fi
  fatal "DNS in chroot broken (deb.debian.org/security.debian.org)"
}

install_base_packages() {
  stage "apt_install"

  mount_chroot_helpers
  exec_net_check_target
  ensure_chroot_dns

  if ! chroot_apt_update; then
    log "[!] apt-get update failed; current target resolv.conf:"
    log_target_resolv_conf
    log "[!] apt-get update failed; retrying with fallback DNS."
    write_resolv_conf_defaults
    ensure_target_nsswitch_dns
    log "[!] retrying apt-get update with fallback resolv.conf:"
    log_target_resolv_conf
    if ! chroot_apt_update; then
      log "[!] fallback DNS failed; retrying with public resolvers."
      write_resolv_conf_public
      ensure_target_nsswitch_dns
      log "[!] retrying apt-get update with public resolvers:"
      log_target_resolv_conf
      chroot_apt_update || fatal "apt-get update failed after retry (check network/DNS)."
    fi
  fi

  local arch grub_pkg kernel_pkg
  arch="$(detect_arch)"
  [[ -n "$arch" ]] || fatal "Unable to detect target architecture for package install"

  case "$arch" in
    amd64) kernel_pkg="linux-image-amd64" ;;
    i386) kernel_pkg="linux-image-686-pae" ;;
    arm64) kernel_pkg="linux-image-arm64" ;;
    armhf) kernel_pkg="linux-image-armmp" ;;
    ppc64el) kernel_pkg="linux-image-ppc64el" ;;
    s390x) kernel_pkg="linux-image-s390x" ;;
    *) kernel_pkg="linux-image-$arch" ;;
  esac

  case "$BOOT_MODE" in
    uefi)
      grub_pkg="grub-efi-$arch"
      ;;
    *)
      case "$arch" in
        amd64|i386) grub_pkg="grub-pc" ;;
        *) grub_pkg="grub-efi-$arch" ;;
      esac
      ;;
  esac

  local net_pkgs="" dhcp_pkg=""
  case "$NET_STACK" in
    ifupdown) net_pkgs="ifupdown" ;;
    networkd|*) net_pkgs="" ;;
  esac

  if [[ "$NET_STACK" == "ifupdown" ]]; then
    if [[ "${NET4_ENABLE:-1}" == "1" && "${NET4_MODE:-dhcp}" == "dhcp" ]]; then
      dhcp_pkg="isc-dhcp-client"
    fi
    if [[ "${NET6_ENABLE:-0}" == "1" && "${NET6_MODE:-dhcp}" == "dhcp" ]]; then
      dhcp_pkg="isc-dhcp-client"
    fi
  fi

  local lvm_pkgs=""
  [[ "$LVM_MODE" != "none" ]] && lvm_pkgs="lvm2"

  chroot_run "apt-get install -y --no-install-recommends ca-certificates systemd-sysv $kernel_pkg $grub_pkg $net_pkgs $dhcp_pkg $lvm_pkgs"
}
