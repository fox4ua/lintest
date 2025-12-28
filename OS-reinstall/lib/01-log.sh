#!/usr/bin/env bash
set -Eeuo pipefail

stage_set() {
  STAGE="$1"
  echo -e "\n[=] stage: ${STAGE}" | tee -a "$LOG_FILE"
}

log()  { echo -e "\n[+] [$STAGE] $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "\n[!] [$STAGE] $*" | tee -a "$LOG_FILE"; }
die()  { echo -e "\n[!] [$STAGE] $*" | tee -a "$LOG_FILE" >&2; exit 1; }

require_root() {
  [[ "${EUID:-0}" -eq 0 ]] || die "Run as root (sudo)."
}

init_log() {
  : > "$LOG_FILE"
  echo "[=] log started: $LOG_FILE" | tee -a "$LOG_FILE"
}

run() {
  local src="${BASH_SOURCE[1]##*/}"
  log "[${src}] $*"
  "$@" 2>&1 | tee -a "$LOG_FILE"
}

run_secret() {
  local src="${BASH_SOURCE[1]##*/}"
  log "[${src}] (secret command redacted)"
  "$@" 2>&1 | tee -a "$LOG_FILE"
}

log_kv() {
  local title="$1"; shift
  log "$title: $*"
}

on_error_trap() {
  local exit_code=$?
  local src="${BASH_SOURCE[1]##*/}"
  local line="${BASH_LINENO[0]:-?}"
  local func="${FUNCNAME[1]:-main}"

  warn "FAILED in ${src}:${line} (${func}), exit=${exit_code}"
  dump_collect || true

  if command -v dialog >/dev/null 2>&1; then
    local tail_lines
    tail_lines="$(tail -n 40 "$LOG_FILE" 2>/dev/null || true)"
    dialog --clear       --backtitle "OVH VPS Rescue Installer"       --title "ERROR"       --msgbox "stage: ${STAGE}
location: ${src}:${line} (${func})
exit code: ${exit_code}

Log:  ${LOG_FILE}
Dump: ${DUMP_TGZ}

Last log lines:
${tail_lines}" 28 100 || true
  fi

  clear || true
  exit "$exit_code"
}

trap on_error_trap ERR INT
