#!/usr/bin/env bash

preflight_validate_env() {
  stage "preflight"

  [[ -n "${DISK:-}" ]] || fatal "DISK is not set"
  [[ -b "${DISK:-}" ]] || fatal "DISK is not a block device: $DISK"
  [[ -n "${BOOT_MODE:-}" ]] || fatal "BOOT_MODE is not set"
  [[ -n "${DEBIAN_SUITE:-}" ]] || fatal "DEBIAN_SUITE is not set"
  [[ -n "${DEBIAN_MIRROR:-}" ]] || fatal "DEBIAN_MIRROR is not set"

  case "$BOOT_MODE" in
    uefi|biosgpt|biosmbr) ;;
    *) fatal "Unknown BOOT_MODE: $BOOT_MODE" ;;
  esac

  case "$LVM_MODE" in
    none|linear|thin) ;;
    *) fatal "Unknown LVM_MODE: $LVM_MODE" ;;
  esac

  [[ -n "${NET_STACK:-}" ]] || fatal "NET_STACK is not set"
  [[ -n "${NET_IFACE:-}" ]] || fatal "NET_IFACE is not set"

  preflight_validate_network_static
}

preflight_validate_network_static() {
  if [[ "${NET4_ENABLE:-1}" == "1" && "${NET4_MODE:-dhcp}" == "static" ]]; then
    [[ -n "${NET4_ADDR:-}" ]] || fatal "NET4_ADDR is required for static IPv4"
    [[ -n "${NET4_GW:-}" ]] || fatal "NET4_GW is required for static IPv4"
  fi

  if [[ "${NET6_ENABLE:-0}" == "1" && "${NET6_MODE:-dhcp}" == "static" ]]; then
    [[ -n "${NET6_ADDR:-}" ]] || fatal "NET6_ADDR is required for static IPv6"
    [[ -n "${NET6_GW:-}" ]] || fatal "NET6_GW is required for static IPv6"
  fi
}
