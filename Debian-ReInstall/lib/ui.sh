#!/usr/bin/env bash

UI_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/ui"

# shellcheck source=/dev/null
source "$UI_DIR/01-welcome.sh"
source "$UI_DIR/02-bios.sh"

ui_init() {
  command -v dialog >/dev/null 2>&1 || {
    echo "dialog not found. Install it: apt-get update && apt-get install -y dialog" >&2
    exit 1
  }
}

ui_clear() {
  dialog --clear
  clear
}

ui_msg() {
  ui_dialog dialog --clear --title "Информация" --msgbox "$1" 12 74
  ui_clear
}

# ВАЖНО:
# - временно отключает errexit/errtrace и ERR trap
# - возвращает реальный exit code dialog (0/1/2/255/…)
ui_dialog() {
  local old_opts old_err_trap rc
  old_opts="$(set +o)"               # снимок всех set -o флагов
  old_err_trap="$(trap -p ERR || true)"

  set +e +E
  trap - ERR

  "$@"
  rc=$?

  # восстановить trap ERR
  if [[ -n "$old_err_trap" ]]; then
    eval "$old_err_trap"
  fi
  # восстановить опции ровно как были
  eval "$old_opts"

  return "$rc"
}
