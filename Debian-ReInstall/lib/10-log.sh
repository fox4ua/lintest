#!/usr/bin/env bash

log_init() {
  : > "$LOG_FILE"
  chmod 600 "$LOG_FILE" 2>/dev/null || true
  log "[=] log started: $LOG_FILE"
}

log() {
  printf '%s [%s] %s\n' "$(date '+%F %T')" "${STAGE:-init}" "$*" >>"$LOG_FILE"
}

stage() {
  STAGE="$1"
  log "[=] stage: $STAGE"
}

on_error() {
  local rc="$1" line="$2" cmd="${3:-}"
  log "[!] FAILED rc=$rc line=$line cmd=${cmd}"
}
