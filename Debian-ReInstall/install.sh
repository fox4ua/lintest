#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export BASE_DIR

# переменные
source "$BASE_DIR/lib/00-env.sh"
# логирование
source "$LIB_DIR/10-log.sh"
# остальное
source "$INIT_DIR/01-require_root.sh"
source "$INIT_DIR/02-boot_detect.sh"
source "$LIB_DIR/ui.sh"


main() {
  log_init
  trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR
  # check root
  require_root
  ui_init

  local boot_mode="" boot_label="" rc

  while true; do
    ui_welcome
    rc=$?
    case "$rc" in
      0) : ;;        # OK -> дальше
      1|255) exit 0 ;; # Cancel/ESC
      *) exit 0 ;;
    esac

    # перед окном выбора:
    local HAS_UEFI=0
    if detect_boot_mode_strict; then
      HAS_UEFI=1
    else
      HAS_UEFI=0
    fi

    ui_pick_boot_mode boot_mode boot_label "$HAS_UEFI"
    case $? in
      0) : ;;        # дальше следующее окно
      2) continue ;; # назад -> welcome
      *) exit 0 ;;
    esac


  done

  ui_msg "Вы выбрали:\n\n${boot_label}\n\n(boot_mode=${boot_mode})"
}

main "$@"
