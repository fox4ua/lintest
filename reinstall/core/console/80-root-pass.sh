#!/usr/bin/env bash
set -Eeuo pipefail

ui_prompt_root_pass_console() {
  local __out_pass="$1"
  local __out_set="$2"
  local p1 p2

  while true; do
    printf "Root password (empty = LOCK root): "
    read -r -s p1; echo
    printf "Confirm root password: "
    read -r -s p2; echo

    if [[ "$p1" != "$p2" ]]; then
      echo "Passwords do not match. Try again."
      continue
    fi

    # Важно: даже если пусто — считаем, что задано (LOCK root)
    printf -v "$__out_pass" '%s' "$p1"
    printf -v "$__out_set" '%s' "1"
    return 0
  done
}
