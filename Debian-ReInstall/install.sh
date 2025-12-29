#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$BASE_DIR/lib"

# shellcheck source=/dev/null
source "$LIB_DIR/ui.sh"

main() {
  ui_init

  local boot_mode="" boot_label=""

  while true; do
    if ! ui_welcome; then
      exit 0
    fi

    if ui_pick_boot_mode boot_mode boot_label; then
      break  # Apply
    else
      case $? in
        2) continue ;; # Back -> Welcome
        *) exit 0 ;;   # Cancel/ESC -> Exit
      esac
    fi
  done

  ui_msg "Вы выбрали:\n\n${boot_label}\n\n(boot_mode=${boot_mode})"
}

main "$@"
