#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_mode_console() {
  local __out_var="$1"
  local ans

  while true; do
    echo "UI mode:"
    echo "  1) none    (no questions; only flags)   [future]"
    echo "  2) console (questions in terminal)      [now]"
    echo "  3) dialog  (windows via dialog/ncurses) [future]"
    printf "Choose [1-3]: "
    read -r ans

    case "$ans" in
      1) printf -v "$__out_var" '%s' "none"; return 0 ;;
      2) printf -v "$__out_var" '%s' "console"; return 0 ;;
      3) printf -v "$__out_var" '%s' "dialog"; return 0 ;;
      *) echo "Invalid choice. Try again." ;;
    esac
  done
}
