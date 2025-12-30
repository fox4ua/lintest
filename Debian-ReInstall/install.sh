#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$BASE_DIR/lib"

# shellcheck source=/dev/null
source "$LIB_DIR/ui.sh"

main() {
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

    ui_pick_boot_mode boot_mode boot_label
    rc=$?
    case "$rc" in
      0) break ;;      # Apply
      2) continue ;;   # Back -> welcome
      1|255) exit 0 ;; # Cancel/ESC
      *) exit 0 ;;
    esac
  done

  ui_msg "Вы выбрали:\n\n${boot_label}\n\n(boot_mode=${boot_mode})"
}

main "$@"
