# lib/exec/10-runner.sh
#!/usr/bin/env bash
# shellcheck shell=bash

# Unified exec runner with step progress (dialog gauge if ui_progress_* exists).
# Requires:
#   - log() function
#   - ui_msg() function
#   - LOG_FILE variable (path to log)
# Optional:
#   - ui_progress_open(title, msg, h, w)
#   - ui_progress_set(percent, msg)
#   - ui_progress_close()

# Internal storage: each item "id|title|weight|fn"
EXEC_RUNNER_STEPS=()

# State for nested progress inside a step
EXEC_RUNNER_TOTAL_WEIGHT=0
EXEC_RUNNER_DONE_WEIGHT=0
EXEC_RUNNER_CUR_STEP_WEIGHT=0
EXEC_RUNNER_CUR_STEP_TITLE=""
EXEC_RUNNER_GAUGE_OPEN=0

exec_runner_reset() {
  EXEC_RUNNER_STEPS=()
  EXEC_RUNNER_TOTAL_WEIGHT=0
  EXEC_RUNNER_DONE_WEIGHT=0
  EXEC_RUNNER_CUR_STEP_WEIGHT=0
  EXEC_RUNNER_CUR_STEP_TITLE=""
  EXEC_RUNNER_GAUGE_OPEN=0
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
  declare -F ui_progress_open >/dev/null 2>&1 || return 1
  declare -F ui_progress_set  >/dev/null 2>&1 || return 1
  declare -F ui_progress_close >/dev/null 2>&1 || return 1
  return 0
}

# Absolute progress update in percent [0..100]
exec_runner_progress_abs() {
  local percent="$1"
  local msg="${2:-}"

  if exec_runner__has_gauge; then
    if (( EXEC_RUNNER_GAUGE_OPEN == 0 )); then
      ui_progress_open "Installer" "Starting..." 10 74
      EXEC_RUNNER_GAUGE_OPEN=1
    fi
    ui_progress_set "$percent" "$msg"
  else
    # Fallback (no dialog)
    log "[=] progress ${percent}% ${msg//$'\n'/ | }"
  fi
}

# Local progress inside current step [0..100], mapped to absolute percent.
# Use inside step functions if you want live updates:
#   exec_progress 30 "Downloading..."
exec_progress() {
  local local_percent="$1"
  local msg="${2:-}"

  local local_done
  local abs_units
  local abs_percent

  # Protect from division by zero
  if (( EXEC_RUNNER_TOTAL_WEIGHT <= 0 )); then
    exec_runner_progress_abs 0 "$msg"
    return 0
  fi

  # Convert local percent within current step to "weight units"
  local_done=$(( EXEC_RUNNER_CUR_STEP_WEIGHT * local_percent / 100 ))
  abs_units=$(( EXEC_RUNNER_DONE_WEIGHT + local_done ))
  abs_percent=$(( abs_units * 100 / EXEC_RUNNER_TOTAL_WEIGHT ))

  if [[ -n "$msg" ]]; then
    exec_runner_progress_abs "$abs_percent" "Step: ${EXEC_RUNNER_CUR_STEP_TITLE}\n${msg}\nLog: ${LOG_FILE}"
  else
    exec_runner_progress_abs "$abs_percent" "Step: ${EXEC_RUNNER_CUR_STEP_TITLE}\nLog: ${LOG_FILE}"
  fi
}

exec_runner__fail() {
  local title="$1"

  # Close gauge before showing message
  if exec_runner__has_gauge && (( EXEC_RUNNER_GAUGE_OPEN == 1 )); then
    ui_progress_close
    EXEC_RUNNER_GAUGE_OPEN=0
  fi

  ui_msg "Step failed: ${title}\n\nLast log lines:\n$(tail -n 80 "${LOG_FILE}" 2>/dev/null || true)"
  return 1
}

# Run all registered steps.
# Usage:
#   exec_runner_run "Installer" "Preparing..."
exec_runner_run() {
  local ui_title="${1:-Installer}"
  local start_msg="${2:-Preparing...}"

  local item id title weight fn
  local abs_percent

  exec_runner__calc_total
  if (( EXEC_RUNNER_TOTAL_WEIGHT <= 0 )); then
    ui_msg "No steps defined for exec runner."
    return 1
  fi

  EXEC_RUNNER_DONE_WEIGHT=0

  # Open gauge (if available) with initial message
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

    log "[=] step:${id} begin (${title})"
    if ! "$fn"; then
      log "[!] step:${id} failed (${title})"
      return "$(exec_runner__fail "$title")"
    fi
    log "[=] step:${id} done (${title})"

    EXEC_RUNNER_DONE_WEIGHT=$(( EXEC_RUNNER_DONE_WEIGHT + weight ))
  done

  exec_runner_progress_abs 100 "Done\nLog: ${LOG_FILE}"

  if exec_runner__has_gauge && (( EXEC_RUNNER_GAUGE_OPEN == 1 )); then
    ui_progress_close
    EXEC_RUNNER_GAUGE_OPEN=0
  fi

  return 0
}
