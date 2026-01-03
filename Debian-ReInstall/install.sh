#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export BASE_DIR

# переменные
source "$BASE_DIR/lib/00-env.sh"
# логирование
source "$LIB_DIR/10-log.sh"
# дополнительные функции
source "$INIT_DIR/01-require_root.sh"
source "$INIT_DIR/02-boot_detect.sh"
source "$INIT_DIR/03-disk_detect.sh"
# остальное

source "$LIB_DIR/ui.sh"


main() {
  log_init
  trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR
  require_root
  ui_init

  local rc state
  state="welcome"

  while :; do
    case "$state" in
      welcome)
        # ui_welcome: 0=Continue, иначе Cancel/ESC
        ui_welcome || exit 0
        if detect_boot_mode_strict; then
          HAS_UEFI=1
        else
          HAS_UEFI=0
        fi
        state="boot"
        ;;

      boot)
        if ui_pick_boot_mode BOOT_MODE BOOT_LABEL "$HAS_UEFI"; then
          rc=0
        else
          rc=$?
        fi

        case "$rc" in
          0) state="disk" ;;
          2) state="welcome" ;;
          *) exit 0 ;;
        esac
        ;;

      disk)
        if ui_pick_disk DISK; then
          rc=0
        else
          rc=$?
        fi

        case "$rc" in
          0) state="lvm" ;;
          2) state="boot" ;;
          *) exit 0 ;;
        esac
        ;;

      lvm)
        rc=0
        ui_pick_lvm_mode LVM_MODE VG_NAME THINPOOL_NAME || rc=$?
        case "$rc" in
          0) state="part_boot" ;;
          2) state="boot" ;;
          *) exit 0 ;;
        esac
        ;;

      part_boot)
        if ui_pick_boot_size BOOT_SIZE_MIB; then
          rc=0
        else
          rc=$?
        fi

        case "$rc" in
          0) state="part_swap" ;;
          2) state="lvm" ;;
          *) exit 0 ;;
        esac
        ;;

      part_swap)
        if ui_pick_swap_size SWAP_SIZE_GIB; then
          rc=0
        else
          rc=$?
        fi

        case "$rc" in
          0) state="part_root" ;;
          2) state="part_boot" ;;
          *) exit 0 ;;
        esac
        ;;

      part_root)
        if ui_pick_root_size ROOT_SIZE_GIB; then
          rc=0
        else
          rc=$?
        fi

        case "$rc" in
          0) state="debian" ;;
          2) state="part_swap" ;;
          *) exit 0 ;;
        esac
        ;;

      debian)
        rc=0
        ui_pick_debian_version DEBIAN_VERSION DEBIAN_SUITE || rc=$?
        case "$rc" in
          0) state="summary" ;;
          2) state="part_root" ;;
          *) exit 0 ;;
        esac
        ;;

      summary)
        ui_msg "План установки:\n\n${BOOT_LABEL}\nДиск: ${DISK}\n\n/boot: ${BOOT_SIZE_MIB} MiB\nswap: ${SWAP_SIZE_GIB} GiB\nroot: ${ROOT_SIZE_GIB} GiB (0=остаток)\n\nLVM_MODE=${LVM_MODE}\nVG_NAME=${VG_NAME}\nTHINPOOL_NAME=${THINPOOL_NAME}\n\nDISK_RELEASE_APPROVED=${DISK_RELEASE_APPROVED:-0}"
        break
        ;;

      *)
        exit 1
        ;;
    esac
  done
}


main "$@"
