#!/usr/bin/env bash

: "${UI_DIR:?}"


# ui
# shellcheck source=/dev/null
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
# hostname / hosts
source "$UI_DIR/30-hostname.sh"
source "$UI_DIR/31-hosts.sh"
# network
source "$UI_DIR/40-net_current.sh"
source "$UI_DIR/41-net_stack.sh"
source "$UI_DIR/42-net_iface.sh"
# IPv4
source "$UI_DIR/43-net4_enable.sh"
source "$UI_DIR/44-net4_mode.sh"
source "$UI_DIR/45-net4_static.sh"
# IPv6
source "$UI_DIR/46-net6_enable.sh"
source "$UI_DIR/47-net6_mode.sh"
source "$UI_DIR/48-net6_static.sh"


source "$UI_DIR/50-root_password.sh"

source "$UI_DIR/90-summary.sh"

ui_init() {
  local -a required_cmds=(dialog lsblk ip findmnt pvs swapon mountpoint curl)
  local -a missing_cmds=()
  local cmd

  for cmd in "${required_cmds[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing_cmds+=("$cmd")
    fi
  done

  if [[ ${#missing_cmds[@]} -eq 0 ]]; then
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    local -a packages=()
    local add_pkg
    add_pkg() {
      local pkg="$1"
      local existing
      for existing in "${packages[@]}"; do
        [[ "$existing" == "$pkg" ]] && return 0
      done
      packages+=("$pkg")
    }

    for cmd in "${missing_cmds[@]}"; do
      case "$cmd" in
        dialog) add_pkg dialog ;;
        lsblk|findmnt|swapon) add_pkg util-linux ;;
        ip) add_pkg iproute2 ;;
        pvs) add_pkg lvm2 ;;
        curl) add_pkg curl ;;
      esac
    done

    export DEBIAN_FRONTEND=noninteractive

    if ! apt-get update -y; then
      echo "Warning: failed to update package lists. Network access may be unavailable." >&2
      exit 1
    fi
    if ! apt-get install -y --no-install-recommends "${packages[@]}"; then
      echo "Warning: failed to install required packages. Please ensure network access and try again." >&2
      exit 1
    fi

    missing_cmds=()
    for cmd in "${required_cmds[@]}"; do
      if ! command -v "$cmd" >/dev/null 2>&1; then
        missing_cmds+=("$cmd")
      fi
    done
  fi

  if [[ ${#missing_cmds[@]} -gt 0 ]]; then
    local msg
    msg="Missing required commands: ${missing_cmds[*]}."
    if command -v dialog >/dev/null 2>&1; then
      ui_dialog dialog --clear --msgbox "$msg" 10 74
      ui_clear
    else
      echo "$msg" >&2
    fi
    exit 1
  fi

  return 0
}
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
