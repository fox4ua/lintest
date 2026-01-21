#!/usr/bin/env bash
# shellcheck shell=bash

# Preflight helpers: boot/iface detection, tool ensuring, DNS/mirror checks.
# Requires: log(), die() from lib/00-log.sh
#           have_cmd(), need_cmd() from lib/01-utils.sh

fetch_release_file() {
  local url="$1"
  if have_cmd curl; then
    curl -fsSL --max-time 10 "$url" >/dev/null
  elif have_cmd wget; then
    wget -qO- --timeout=10 "$url" >/dev/null
  else
    die "Missing command: curl or wget (need one for mirror check)"
  fi
}

ensure_pkg_tools() {
  if ! have_cmd apt-get; then
    die "apt-get not found in rescue env. Use a rescue image with apt-get."
  fi
  if ! have_cmd curl && ! have_cmd wget; then
    log "Installing curl (no curl/wget present)..."
    apt-get update
    apt-get install -y ca-certificates curl
  fi
}

ensure_debootstrap() {
  if have_cmd debootstrap; then return 0; fi
  ensure_pkg_tools
  log "debootstrap not found. Installing debootstrap..."
  apt-get update
  apt-get install -y debootstrap
  have_cmd debootstrap || die "Failed to install debootstrap"
}

ensure_lvm_tools() {
  # Expects LVM_MODE to be set/validated by caller.
  if [[ "${LVM_MODE:-none}" == "none" ]]; then return 0; fi
  if have_cmd pvcreate && have_cmd vgcreate && have_cmd lvcreate && have_cmd lvs && have_cmd vgs; then return 0; fi
  ensure_pkg_tools
  log "LVM tools not found. Installing lvm2..."
  apt-get update
  apt-get install -y lvm2
  have_cmd pvcreate || die "Failed to install lvm2"
}

preflight_detect_boot_mode() {
  # Uses/sets BOOT_MODE
  if [[ "${BOOT_MODE:-auto}" == "auto" ]]; then
    [[ -d /sys/firmware/efi ]] && BOOT_MODE="uefi" || BOOT_MODE="bios"
  fi
  [[ "$BOOT_MODE" == "uefi" || "$BOOT_MODE" == "bios" ]] || die "BOOT_MODE must be auto|uefi|bios"
}

preflight_detect_iface() {
  # Uses/sets IFACE
  if [[ -z "${IFACE:-}" ]]; then
    IFACE="$(ip -o link show 2>/dev/null | awk -F': ' '$2 !~ /^(lo|docker|veth|br-|virbr|tun|tap)/ {print $2; exit}')"
  fi
  [[ -n "${IFACE:-}" ]] || die "Could not auto-detect IFACE; set --iface"
}

preflight_check_time() {
  local y
  y="$(date -u +%Y 2>/dev/null || echo 0)"
  if ! [[ "$y" =~ ^[0-9]+$ ]]; then
    return 0
  fi
  if (( y < 2020 )); then
    log "WARN: System time seems wrong (year=$y). apt/debootstrap may fail. Fix time or enable NTP."
  fi
}

preflight_check_dns_mirror() {
  # Requires: RELEASE, MIRROR
  log "Checking DNS resolution..."
  getent ahostsv4 deb.debian.org >/dev/null 2>&1 || die "DNS failed for deb.debian.org (fix /etc/resolv.conf in rescue)"

  log "Checking mirror reachability: $MIRROR (release=$RELEASE)"
  fetch_release_file "$MIRROR/dists/$RELEASE/Release" || die "Mirror not reachable or release not found"
}

preflight_refuse_if_current_root_disk() {
  # Refuse installing onto the disk that hosts current /. Useful in rescue with multiple disks.
  local root_src root_base
  root_src="$(findmnt -no SOURCE / 2>/dev/null || true)"
  root_base=""

  if [[ -n "$root_src" && -b "$root_src" ]]; then
    root_base="$(lsblk -no PKNAME "$root_src" 2>/dev/null || true)"
  fi
  if [[ -n "$root_base" && "/dev/$root_base" == "${DISK:-}" ]]; then
    die "Refusing to install onto current root disk: $DISK"
  fi
}

preflight_validate_static_net() {
  if [[ "${NET_MODE:-dhcp}" == "static" ]]; then
    [[ -n "${IP_ADDR:-}" && -n "${GW_ADDR:-}" ]] || die "Static net requires --ip (CIDR) and --gw"
  fi
}
