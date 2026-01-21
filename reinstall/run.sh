#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

ui_mode="dialog"
remaining_args=()
help_requested=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      help_requested=1
      shift 1
      ;;
    --ui)
      [[ $# -ge 2 ]] || { echo "ERROR: Missing value for --ui" >&2; exit 1; }
      ui_mode="$2"
      shift 2
      ;;
    --ui=*)
      ui_mode="${1#*=}"
      shift 1
      ;;
    *)
      remaining_args+=("$1")
      shift 1
      ;;
  esac
 done

if [[ "$help_requested" -eq 1 ]]; then
  cat <<'USAGE_EOF'
Usage:
  ./ui.sh [--ui none|console|dialog] [options]

Behavior:
  --ui none      run install.sh with all remaining options
  --ui console   (planned) ignore other options
  --ui dialog    (planned) ignore other options
  (default)      dialog (planned)
USAGE_EOF
  if [[ "$ui_mode" == "none" ]]; then
    exec "$BASE_DIR/install.sh" --help
  fi
  echo "Tip: use --ui none --help to see installer options."
  exit 0
fi

case "$ui_mode" in
  none)
    if [[ ! -x "$BASE_DIR/install.sh" ]]; then
      echo "ERROR: install.sh not found or not executable in $BASE_DIR" >&2
      exit 1
    fi
    exec "$BASE_DIR/install.sh" "${remaining_args[@]}"
    ;;
  console)
    echo "Console UI not implemented yet. Ignoring other flags."
    ;;
  dialog|"")
    echo "Dialog UI not implemented yet. Ignoring other flags."
    ;;
  *)
    echo "ERROR: Unknown --ui value: $ui_mode" >&2
    exit 1
    ;;
esac
