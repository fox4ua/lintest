#!/usr/bin/env bash
# shellcheck shell=bash

# Generic helper functions used across stages/libs.
# Requires: log(), die() (from lib/00-log.sh)

have_cmd() { command -v "$1" >/dev/null 2>&1; }

need_cmd() { have_cmd "$1" || die "Missing command: $1"; }

confirm() {
  local msg="$1"
  if [[ "${ASSUME_YES:-0}" == "1" ]]; then
    log "Auto-confirm: $msg"
    return 0
  fi
  local ans
  read -r -p "$msg [y/N]: " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

valid_size() {
  # Accepts: <int>[K|M|G|T] (upper/lower)
  [[ "$1" =~ ^[0-9]+[kKmMgGtT]$ ]]
}

parse_size_to_bytes() {
  # Minimal parser: 30G -> bytes (base 1024)
  local s="$1"
  local n unit mul
  n="${s%[kKmMgGtT]}"
  unit="${s:${#s}-1:1}"
  case "${unit^^}" in
    K) mul=1024 ;;
    M) mul=$((1024*1024)) ;;
    G) mul=$((1024*1024*1024)) ;;
    T) mul=$((1024*1024*1024*1024)) ;;
    *) die "Bad size unit: $s" ;;
  esac
  echo $(( n * mul ))
}

