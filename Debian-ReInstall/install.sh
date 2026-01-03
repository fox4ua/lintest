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
  # check root
  require_root
  ui_init

  local rc=0

  while true; do
    # 1) welcome
    ui_welcome || exit 0

    # 2) detect uefi BEFORE boot menu
    if detect_boot_mode_strict; then HAS_UEFI=1; else HAS_UEFI=0; fi

    # 3) boot menu
    while true; do
      rc=0
      ui_pick_boot_mode BOOT_MODE BOOT_LABEL "$HAS_UEFI" || rc=$?
      case "$rc" in
        0) : ;;          # OK -> идём к выбору диска
        2) break ;;      # Back -> на welcome
        *) exit 0 ;;     # Cancel/ESC
      esac

      # 4) disk menu (Back -> обратно в boot menu)
    # Step 3: Disk
      while true; do
        rc=0
        ui_pick_disk DISK || rc=$?
        case "$rc" in
          0) : ;;
          2) break ;;     # back -> boot mode
          *) exit 0 ;;
        esac

        # Step 4: Partition sizes
        rc=0
        ui_pick_partition_sizes BOOT_SIZE_MIB SWAP_SIZE_GIB ROOT_SIZE_GIB "$DISK" || rc=$?
        case "$rc" in
          0) break ;;     # ok -> выходим из disk-loop и из общего цикла
          2) continue ;;  # back -> снова выбор диска
          *) exit 0 ;;
        esac
      done
    done
  done


  ui_msg "Вы выбрали:\n\n${BOOT_LABEL}\nДиск: ${DISK}\n\nBOOT_MODE=${BOOT_MODE}\nHAS_UEFI=${HAS_UEFI}"
}

main "$@"
