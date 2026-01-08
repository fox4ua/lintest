#!/usr/bin/env bash

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

    if ! apt-get update; then
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
      dialog --clear --msgbox "$msg" 10 74
      dialog --clear
      clear
    else
      echo "$msg" >&2
    fi
    exit 1
  fi

  return 0
}
