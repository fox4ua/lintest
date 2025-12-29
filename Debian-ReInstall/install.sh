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
    ui_welcome || exit 0

    ui_pick_boot_mode boot_mode boot_label
    case $? in
      0) break ;;
      2) continue ;;
      1) exit 0 ;;
    esac
  done

  ui_msg "Вы выбрали:\n\n${boot_label}\n\n(boot_mode=${boot_mode})"
}

main "$@"
