#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/00-env.sh"
source "${LIB_DIR}/01-log.sh"
source "${LIB_DIR}/90-dump.sh"
source "${LIB_DIR}/03-deps.sh"
source "${LIB_DIR}/05-preflight.sh"
source "${LIB_DIR}/02-ui.sh"
source "${LIB_DIR}/10-disk.sh"
source "${LIB_DIR}/20-net.sh"
source "${LIB_DIR}/30-install.sh"
source "${LIB_DIR}/40-bootloader.sh"

main() {
  require_root
  init_log
  stage_set "preflight"

  BOOT_MODE="$(detect_boot_mode_strict)"
  ensure_deps_rescue "$BOOT_MODE"
  preflight_reset_state
  preflight_check_rescue_mode_hint
  preflight_check_time_dns

  ui_welcome "$BOOT_MODE"

  DISK="$(ui_pick_disk)"
  preflight_check_rescue_not_on_disk "$DISK"

  SWAP_GB="$(ui_pick_swap)"
  BOOT_SEL="$(ui_pick_boot)"
  BOOT_MIB="$(boot_label_to_mib "$BOOT_SEL")"
  LVM_MODE="$(ui_pick_lvm_mode)"
  ROOT_GB="$(ui_input_root_size)"
  DEBREL="$(ui_pick_debian)"
  MIRROR="$(ui_pick_mirror)"
  HOSTNAME="$(ui_input_hostname)"

  IFACE="$(ui_pick_iface)"
  NET_BACKEND="$(ui_pick_net_backend)"
  NET_MODE="$(ui_pick_net_mode)"

  STATIC_PROFILE=""
  STATIC_DATA=""
  if [[ "$NET_MODE" == "static" ]]; then
    STATIC_PROFILE="$(ui_pick_static_profile)"
    STATIC_DATA="$(ui_input_static "$STATIC_PROFILE")"
  fi

  preflight_check_mirror "$MIRROR" "$DEBREL"
  ROOT_PASS="$(ui_input_root_password)"

  disk_prepare_and_partition "$DISK" "$BOOT_MODE" "$BOOT_MIB" "$SWAP_GB"
  disk_resolve_partitions "$DISK" "$BOOT_MODE"
  disk_format_partitions "$BOOT_MODE" "$P1" "$P2" "$P3"
  disk_create_lvm "$P4" "$ROOT_GB" "$LVM_MODE"
  disk_mount_target "$BOOT_MODE" "$P1" "$P2" "$P3"

  install_debian "$DEBREL" "$MIRROR"
  install_write_basic_config "$HOSTNAME" "$IFACE" "$NET_BACKEND" "$NET_MODE" "$STATIC_PROFILE" "$STATIC_DATA" "$BOOT_MODE" "$P1" "$P2" "$P3"

  install_set_root_password "$ROOT_PASS"
  unset ROOT_PASS

  install_base_packages "$NET_BACKEND"
  bootloader_install "$BOOT_MODE" "$DISK"

  ui_done_and_reboot "$BOOT_MODE" "$LVM_MODE" "$NET_MODE" "$IFACE" "$NET_BACKEND"
}

main "$@"
