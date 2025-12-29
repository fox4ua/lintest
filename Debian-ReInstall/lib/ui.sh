#!/usr/bin/env bash

UI_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/ui"

source "$UI_DIR/welcome.sh"
source "$UI_DIR/bios.sh"

ui_init() {
  if ! command -v dialog >/dev/null 2>&1; then
    echo "dialog not found. Install it first." >&2
    exit 1
  fi
}

ui_clear() {
  dialog --clear
  clear
}

ui_msg() {
  dialog --clear --title "Информация" --msgbox "$1" 12 74
  ui_clear
}
