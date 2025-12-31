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
      rc=0
      ui_pick_disk DISK || rc=$?
      case "$rc" in
        0) break 2 ;;    # всё выбрано -> выходим из обоих циклов
        2) continue ;;   # Back -> обратно к boot menu
        *) exit 0 ;;     # Cancel/ESC
      esac
    done
  done


  ui_msg "Вы выбрали:\n\n${BOOT_LABEL}\nДиск: ${DISK}\n\nBOOT_MODE=${BOOT_MODE}\nHAS_UEFI=${HAS_UEFI}"
}

main "$@"
