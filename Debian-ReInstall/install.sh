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
    # окно приветствия
    ui_welcome
    rc=$?
    case "$rc" in
      0) : ;;
      1|255) exit 0 ;;
      *) exit 0 ;;
    esac
    # проверка UEFI/Legacy
    if detect_boot_mode_strict; then HAS_UEFI=1; else HAS_UEFI=0; fi

    rc=0
    ui_pick_boot_mode BOOT_MODE BOOT_LABEL "$HAS_UEFI" || rc=$?
    case "$rc" in
      0) break ;;     # выбор принят -> следующее окно
      2) continue ;;  # back -> welcome
      1|255) exit 0 ;;# cancel/esc
      *) exit 0 ;;
    esac
  done



  ui_msg "Вы выбрали:\n\n${BOOT_LABEL}\n\n(boot_mode=${BOOT_MODE})"
}

main "$@"
