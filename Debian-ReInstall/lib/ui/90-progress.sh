#!/usr/bin/env bash
# shellcheck shell=bash

# Использует dialog напрямую; при необходимости замени на ui_dialog dialog ...
ui_progress_open() {
  local title="${1:-Executing}"
  local msg="${2:-Starting...}"
  local h="${3:-10}"
  local w="${4:-70}"

  UI_GAUGE_DIR="$(mktemp -d -t gauge.XXXXXX)"
  UI_GAUGE_FIFO="${UI_GAUGE_DIR}/fifo"
  mkfifo "$UI_GAUGE_FIFO"

  dialog --clear --title "$title" --gauge "$msg" "$h" "$w" 0 <"$UI_GAUGE_FIFO" &
  UI_GAUGE_PID=$!

  # FD 3 -> FIFO writer
  exec 3>"$UI_GAUGE_FIFO"
}

ui_progress_set() {
  local percent="$1"
  local msg="${2:-}"
  # Обновление процента + текста (формат dialog gauge)
  printf '%s\nXXX\n%s\nXXX\n' "$percent" "$msg" >&3
}

ui_progress_close() {
  # Закрыть writer, дождаться dialog, удалить FIFO
  exec 3>&- || true
  [[ -n "${UI_GAUGE_PID:-}" ]] && wait "$UI_GAUGE_PID" 2>/dev/null || true
  [[ -n "${UI_GAUGE_FIFO:-}" ]] && rm -f "$UI_GAUGE_FIFO" || true
  [[ -n "${UI_GAUGE_DIR:-}" ]] && rmdir "$UI_GAUGE_DIR" 2>/dev/null || true
  unset UI_GAUGE_PID UI_GAUGE_FIFO UI_GAUGE_DIR
}
