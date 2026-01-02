#!/usr/bin/env bash

: "${UI_DIR:?}"
: "${INIT_DIR:?}"

# init (детекты/утилиты, которые могут понадобиться UI)
# shellcheck source=/dev/null


# ui
# shellcheck source=/dev/null
source "$UI_DIR/01-welcome.sh"
source "$UI_DIR/02-bios.sh"
source "$UI_DIR/03-disk.sh"

ui_init() {
  if command -v dialog >/dev/null 2>&1; then
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends dialog
    command -v dialog >/dev/null 2>&1 || {
      echo "Failed to install dialog" >&2
      exit 1
    }
    return 0
  fi

  echo "No supported package manager to install dialog automatically." >&2
  exit 1
}
# очистка экрана
ui_clear() {
  dialog --clear
  clear
}

# Вывод конечного результата
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
