#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$BASE_DIR/lib"

# shellcheck source=/dev/null
source "$LIB_DIR/init/01-init.sh"
source "$LIB_DIR/ui.sh"

main() {
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
