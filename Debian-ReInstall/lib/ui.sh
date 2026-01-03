#!/usr/bin/env bash

: "${UI_DIR:?}"


# ui
# shellcheck source=/dev/null
source "$UI_DIR/01-welcome.sh"
source "$UI_DIR/02-bios.sh"
source "$UI_DIR/03-disk.sh"
# lvm
source "$UI_DIR/04-lvm.sh"
# partitions
source "$UI_DIR/05-boot_size.sh"
source "$UI_DIR/06-swap_size.sh"
source "$UI_DIR/07-root_size.sh"
# debian
source "$UI_DIR/08-debian_version.sh"
# mirror
source "$UI_DIR/09-mirror.sh"
# hostname / hosts
source "$UI_DIR/10-hostname.sh"
source "$UI_DIR/11-hosts.sh"

source "$UI_DIR/12-net_iface.sh"

source "$UI_DIR/13-net_mode.sh"

source "$UI_DIR/14-net_static.sh"

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
