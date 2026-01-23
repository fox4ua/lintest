#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_root_size_console() {
  local __out_var="$1"
  local val

  while true; do
    printf "Root size (пример: 30G): "
    read -r val
    [[ "$val" =~ ^[0-9]+[GM]$ ]] || { echo "Invalid. Use like 30G or 20480M."; continue; }
    printf -v "$__out_var" '%s' "$val"
    return 0
  done
}
