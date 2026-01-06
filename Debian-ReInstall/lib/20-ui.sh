#!/usr/bin/env bash

: "${UI_DIR:?}"


# ui
# welcome
source "$UI_DIR/00-welcome.sh"
source "$UI_DIR/02-bios.sh"
source "$UI_DIR/10-disk.sh"
# lvm
source "$UI_DIR/11-lvm.sh"
# partitions
source "$UI_DIR/12-boot_size.sh"
source "$UI_DIR/13-swap_size.sh"
source "$UI_DIR/14-root_size.sh"
# debian
source "$UI_DIR/20-debian_version.sh"
# mirror
source "$UI_DIR/21-mirror.sh"
# network
source "$UI_DIR/30-net_current.sh"
source "$UI_DIR/31-net_stack.sh"
source "$UI_DIR/32-net_iface.sh"
# IPv4
source "$UI_DIR/33-net4_enable.sh"
source "$UI_DIR/34-net4_mode.sh"
source "$UI_DIR/35-net4_static.sh"
# IPv6
source "$UI_DIR/36-net6_enable.sh"
source "$UI_DIR/37-net6_mode.sh"
source "$UI_DIR/38-net6_static.sh"
# hostname / hosts
source "$UI_DIR/40-hostname.sh"
source "$UI_DIR/41-hosts.sh"
# root password
source "$UI_DIR/50-root_password.sh"
# summary info
source "$UI_DIR/90-summary.sh"

# очистка экрана
ui_clear() {
  dialog --clear
  clear
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

ui_msg() {
  local msg="${1:-}"

  if command -v dialog >/dev/null 2>&1; then
    ui_dialog dialog --clear --msgbox "$msg" 10 74
    ui_clear
  else
    echo -e "$msg" >&2
  fi
}
