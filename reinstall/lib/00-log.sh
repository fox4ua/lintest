#!/usr/bin/env bash
# shellcheck shell=bash

log() {
  # LOG_FILE is expected to be set by caller
  local ts
  ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  if [[ -n "${LOG_FILE:-}" ]]; then
    printf '[%s] %s\n' "$ts" "$*" | tee -a "$LOG_FILE" >&2
  else
    printf '[%s] %s\n' "$ts" "$*" >&2
  fi
}

die() {
  log "ERROR: $*"
  exit 1
}

on_err() {
  local ec=$?
  # args: line cmd
  log "FAILED (exit=$ec) at line ${1:-?}: ${2:-?}"
  exit "$ec"
}
