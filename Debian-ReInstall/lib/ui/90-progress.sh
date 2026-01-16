#!/usr/bin/env bash
# shellcheck shell=bash

# dialog gauge wrapper via FIFO

ui_term_restore() {
  # Best-effort terminal restore for ncurses apps (dialog, mc, etc.)
  local tty_out="/dev/null"
  if [[ -w /dev/tty ]]; then
    tty_out="/dev/tty"
  fi

  stty sane 2>/dev/null || true
  tput sgr0 >"$tty_out" 2>/dev/null || true
  tput cnorm >"$tty_out" 2>/dev/null || true
  tput rmcup >"$tty_out" 2>/dev/null || true
  dialog --clear >"$tty_out" 2>/dev/null || true
  clear >"$tty_out" 2>/dev/null || true
  # If running under Midnight Commander, a stronger reset helps avoid screen corruption
  if [[ -n "${MC_SID:-}" ]]; then
    reset 2>/dev/null || true
  fi

}

ui_progress_open() {
  local title="${1:-Executing}"
  local msg="${2:-Starting...}"
  local h="${3:-10}"
  local w="${4:-70}"

  UI_GAUGE_FIFO="$(mktemp -u "/tmp/gauge.XXXXXX")"
  mkfifo "$UI_GAUGE_FIFO"

  dialog --clear --title "$title" --gauge "$msg" "$h" "$w" 0 <"$UI_GAUGE_FIFO" &
  UI_GAUGE_PID=$!

  # writer FD
  exec 3>"$UI_GAUGE_FIFO"
}

ui_progress_set() {
  local percent="$1"
  local msg="${2:-}"
  if [[ ! -e "/proc/$$/fd/3" ]]; then
    return 0
  fi
  printf '%s\nXXX\n%s\nXXX\n' "$percent" "$msg" >&3
}

ui_progress_close() {
  # Close writer FD (dialog will exit when FIFO reaches EOF)
  exec 3>&- 2>/dev/null || true

  # Ensure dialog process is gone
  if [[ -n "${UI_GAUGE_PID:-}" ]]; then
    kill -TERM "$UI_GAUGE_PID" 2>/dev/null || true
    wait "$UI_GAUGE_PID" 2>/dev/null || true
  fi

  [[ -n "${UI_GAUGE_FIFO:-}" ]] && rm -f "$UI_GAUGE_FIFO" || true
  unset UI_GAUGE_PID UI_GAUGE_FIFO

  ui_term_restore
}
