#!/usr/bin/env bash
# shellcheck shell=bash

# lib/exec/10-runner.sh
#
# Unified exec runner with step progress (dialog gauge if ui_progress_* exists).
#
# Requires:
#   - log() function
#   - ui_msg() function
#   - LOG_FILE variable (path to log)
# Optional (for gauge):
#   - ui_progress_open(title, msg, h, w)
#   - ui_progress_set(percent, msg)
#   - ui_progress_close()
#
# Step format: "id|title|weight|fn"

# Minimum time (seconds) to keep each step visible in gauge.
# Set to 0 to disable delays.
: "${EXEC_RUNNER_MIN_STEP_SECONDS:=2}"

EXEC_RUNNER_STEPS=()

EXEC_RUNNER_TOTAL_WEIGHT=0
EXEC_RUNNER_DONE_WEIGHT=0
EXEC_RUNNER_CUR_STEP_WEIGHT=0
EXEC_RUNNER_CUR_STEP_TITLE=""
EXEC_RUNNER_GAUGE_OPEN=0
EXEC_RUNNER_UI_TITLE="Installer"

exec_runner_reset() {
  EXEC_RUNNER_STEPS=()
  EXEC_RUNNER_TOTAL_WEIGHT=0
  EXEC_RUNNER_DONE_WEIGHT=0
  EXEC_RUNNER_CUR_STEP_WEIGHT=0
  EXEC_RUNNER_CUR_STEP_TITLE=""
  EXEC_RUNNER_GAUGE_OPEN=0
  EXEC_RUNNER_UI_TITLE="Installer"
}

exec_runner_add_step() {
  local id="$1"
  local title="$2"
  local weight="$3"
  local fn="$4"

  [[ -n "$id" && -n "$title" && -n "$weight" && -n "$fn" ]] || return 1
  EXEC_RUNNER_STEPS+=("${id}|${title}|${weight}|${fn}")
}

exec_runner__calc_total() {
  local item id title weight fn
  local total=0

  for item in "${EXEC_RUNNER_STEPS[@]}"; do
    IFS='|' read -r id title weight fn <<<"$item"
    total=$(( total + weight ))
  done

  EXEC_RUNNER_TOTAL_WEIGHT="$total"
}

exec_runner__has_gauge() {
  command -v dialog >/dev/null 2>&1 || return 1
  declare -F ui_progress_open  >/dev/null 2>&1 || return 1
  declare -F ui_progress_set   >/dev/null 2>&1 || return 1
  declare -F ui_progress_close >/dev/null 2>&1 || return 1
  return 0
}

exec_runner__ensure_gauge_open() {
  local msg="${1:-Starting...}"
  if exec_runner__has_gauge; then
    if (( EXEC_RUNNER_GAUGE_OPEN == 0 )); then
      ui_progress_open "$EXEC_RUNNER_UI_TITLE" "$msg" 10 74
      EXEC_RUNNER_GAUGE_OPEN=1
    fi
  fi
}

exec_runner_progress_abs() {
  local percent="$1"
  local msg="${2:-}"

  if exec_runner__has_gauge; then
    exec_runner__ensure_gauge_open "$msg"
    ui_progress_set "$percent" "$msg"
  else
    log "[=] progress ${percent}% ${msg//$'\n'/ | }"
  fi
}

# Local progress inside current step [0..100], mapped to absolute percent.
# Use inside step functions for live updates:
#   exec_progress 30 "Downloading..."
exec_progress() {
  local local_percent="$1"
  local msg="${2:-}"

  if (( EXEC_RUNNER_TOTAL_WEIGHT <= 0 )); then
    exec_runner_progress_abs 0 "$msg"
    return 0
  fi

  local local_done=$(( EXEC_RUNNER_CUR_STEP_WEIGHT * local_percent / 100 ))
  local abs_units=$(( EXEC_RUNNER_DONE_WEIGHT + local_done ))
  local abs_percent=$(( abs_units * 100 / EXEC_RUNNER_TOTAL_WEIGHT ))

  if [[ -n "$msg" ]]; then
    exec_runner_progress_abs "$abs_percent" "Step: ${EXEC_RUNNER_CUR_STEP_TITLE}\n${msg}\nLog: ${LOG_FILE}"
  else
    exec_runner_progress_abs "$abs_percent" "Step: ${EXEC_RUNNER_CUR_STEP_TITLE}\nLog: ${LOG_FILE}"
  fi
}

exec_runner__close_gauge() {
  if exec_runner__has_gauge && (( EXEC_RUNNER_GAUGE_OPEN == 1 )); then
    ui_progress_close
    EXEC_RUNNER_GAUGE_OPEN=0
  fi
}

exec_runner__fail() {
  local title="$1"
  exec_runner__close_gauge
  ui_msg "Step failed: ${title}\n\nLast log lines:\n$(tail -n 80 "${LOG_FILE}" 2>/dev/null || true)"
  return 1
}

exec_runner__enforce_min_step_time() {
  local start_seconds="$1"
  local min_seconds="${2:-$EXEC_RUNNER_MIN_STEP_SECONDS}"

  (( min_seconds > 0 )) || return 0

  local elapsed=$(( SECONDS - start_seconds ))
  if (( elapsed < min_seconds )); then
    sleep $(( min_seconds - elapsed ))
  fi
}

# Run all registered steps.
# Usage:
#   exec_runner_run "Installer" "Preparing..."
exec_runner_run() {
  local ui_title="${1:-Installer}"
  local start_msg="${2:-Preparing...}"

  local item id title weight fn
  local abs_percent
  local step_start

  : "${LOG_FILE:?LOG_FILE is required}"

  exec_runner__calc_total
  if (( EXEC_RUNNER_TOTAL_WEIGHT <= 0 )); then
    ui_msg "No steps defined for exec runner."
    return 1
  fi

  EXEC_RUNNER_UI_TITLE="$ui_title"
  EXEC_RUNNER_DONE_WEIGHT=0

  # Open gauge once (if available)
  if exec_runner__has_gauge; then
    ui_progress_open "$ui_title" "$start_msg" 10 74
    EXEC_RUNNER_GAUGE_OPEN=1
    ui_progress_set 0 "$start_msg"
  else
    log "[=] ${ui_title}: ${start_msg}"
  fi

  for item in "${EXEC_RUNNER_STEPS[@]}"; do
    IFS='|' read -r id title weight fn <<<"$item"

    EXEC_RUNNER_CUR_STEP_WEIGHT="$weight"
    EXEC_RUNNER_CUR_STEP_TITLE="$title"

    abs_percent=$(( EXEC_RUNNER_DONE_WEIGHT * 100 / EXEC_RUNNER_TOTAL_WEIGHT ))
    exec_runner_progress_abs "$abs_percent" "Step: ${title}\nLog: ${LOG_FILE}"

    step_start="$SECONDS"

    log "[=] step:${id} begin (${title})"
    if ! "$fn"; then
      log "[!] step:${id} failed (${title})"
      exec_runner__fail "$title"
      return 1
    fi
    log "[=] step:${id} done (${title})"

    exec_runner__enforce_min_step_time "$step_start" "$EXEC_RUNNER_MIN_STEP_SECONDS"

    EXEC_RUNNER_DONE_WEIGHT=$(( EXEC_RUNNER_DONE_WEIGHT + weight ))
  done

  exec_runner_progress_abs 100 "Done\nLog: ${LOG_FILE}"
  exec_runner__close_gauge
  return 0
}
