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

    if ! ui_pick_boot_mode boot_mode boot_label; then
      exit 0
    fi

    # Если выбран "Назад" — возвращаемся на welcome
    if [[ "${UI_BACK:-0}" -eq 1 ]]; then
      continue
    fi

    # Иначе выбор сделан
    break
  done

  ui_msg "Вы выбрали:\n\n${boot_label}\n\n(boot_mode=${boot_mode})"
}

main "$@"
