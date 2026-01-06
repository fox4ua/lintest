#!/usr/bin/env bash

validate_required_fields() {
  local -a missing_fields=()
  local next_stage=""

  add_missing_field() {
    local field="$1"
    local stage_name="$2"

    missing_fields+=("$field")
    if [[ -z "$next_stage" ]]; then
      next_stage="$stage_name"
    fi
  }

  [[ -z "${DISK:-}" ]] && add_missing_field "DISK" "disk"
  [[ -z "${BOOT_MODE:-}" ]] && add_missing_field "BOOT_MODE" "boot"
  [[ -z "${DEBIAN_VERSION:-}" ]] && add_missing_field "DEBIAN_VERSION" "debian"
  [[ -z "${DEBIAN_MIRROR:-}" ]] && add_missing_field "DEBIAN_MIRROR" "mirror"
  [[ -z "${NET_STACK:-}" ]] && add_missing_field "NET_STACK" "net_stack"
  [[ -z "${NET_IFACE:-}" ]] && add_missing_field "NET_IFACE" "net_iface"
  [[ -z "${HOSTNAME_SHORT:-}" ]] && add_missing_field "HOSTNAME_SHORT" "hostname"
  [[ -z "${ROOT_PASS:-}" ]] && add_missing_field "ROOT_PASS" "root_pass"

  if [[ "${NET4_MODE:-}" == "static" ]]; then
    [[ -z "${NET4_ADDR:-}" ]] && add_missing_field "NET4_ADDR" "net_static"
    [[ -z "${NET4_GW:-}" ]] && add_missing_field "NET4_GW" "net_static"
  fi

  if [[ ${#missing_fields[@]} -gt 0 ]]; then
    local msg="Отсутствуют обязательные поля:\n"
    local field

    for field in "${missing_fields[@]}"; do
      msg+="- ${field}\n"
    done

    ui_msg "$msg"
    REQUIRED_FIELDS_STAGE="$next_stage"
    return 1
  fi

  REQUIRED_FIELDS_STAGE=""
  return 0
}
