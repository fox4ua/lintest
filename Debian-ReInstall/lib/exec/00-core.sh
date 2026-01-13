#!/usr/bin/env bash

# Core helpers for execute phase.

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1
}

fatal() {
  local msg="$1"
  log "[!] $msg"
  ui_msg "$msg\n\nLog: $LOG_FILE"
  exit 1
}

run() {
  log "[>] $*"
  "$@" >>"$LOG_FILE" 2>&1
}

run_quiet() {
  "$@" >>"$LOG_FILE" 2>&1
}

part_path() {
  local disk="$1" idx="$2"
  if [[ "$disk" =~ nvme[0-9]+n[0-9]+$ ]]; then
    printf '%sp%s' "$disk" "$idx"
  else
    printf '%s%s' "$disk" "$idx"
  fi
}

array_add_unique() {
  local item="$1"
  local -n arr="$2"
  local existing
  for existing in "${arr[@]}"; do
    [[ "$existing" == "$item" ]] && return 0
  done
  arr+=("$item")
}

detect_arch() {
  local arch
  arch="$(dpkg --print-architecture 2>/dev/null || true)"
  if [[ -z "$arch" ]]; then
    case "$(uname -m 2>/dev/null || true)" in
      x86_64) arch="amd64" ;;
      i386|i686) arch="i386" ;;
      aarch64) arch="arm64" ;;
      armv7l) arch="armhf" ;;
      ppc64le) arch="ppc64el" ;;
      s390x) arch="s390x" ;;
    esac
  fi
  printf '%s' "$arch"
}
