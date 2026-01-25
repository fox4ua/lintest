#!/usr/bin/env bash
set -Eeuo pipefail

# Read a secret value from tty (no echo). Falls back to plain read if stty not available.
_read_secret() {
  local prompt="$1"
  local out_var="$2"
  local val=""

  if command -v stty >/dev/null 2>&1; then
    local stty_state=""
    stty_state="$(stty -g 2>/dev/null || true)"
    trap '[[ -n "$stty_state" ]] && stty "$stty_state"' RETURN
    printf "%s" "$prompt" >&2
    stty -echo
    IFS= read -r val
    [[ -n "$stty_state" ]] && stty "$stty_state"
    trap - RETURN
    printf "\n" >&2
  else
    # fallback (will echo)
    printf "%s" "$prompt" >&2
    IFS= read -r val
  fi

  printf -v "$out_var" '%s' "$val"
}

# --root-pass (required)
# empty -> NOT allowed
# "0" -> cancel
# Returns: 0 ok, 1 cancel
ui_pick_root_pass_console() {
  local out_var="$1"
  local p1="" p2=""

  while true; do
    echo "Root password (--root-pass) [required]"
    echo "  Enter 0 to Cancel"

    _read_secret "Root password: " p1
    [[ "$p1" == "0" ]] && { p1=""; return 1; }
    [[ -n "$p1" ]] || { echo "Password cannot be empty."; echo; continue; }

    _read_secret "Confirm password: " p2
    [[ "$p2" == "0" ]] && { p1=""; p2=""; return 1; }

    if [[ "$p1" != "$p2" ]]; then
      echo "Passwords do not match. Try again."
      echo
      p1=""; p2=""
      continue
    fi

    # минимальная проверка "не совсем слабый" (без фанатизма)
    if (( ${#p1} < 8 )); then
      echo "Password too short (min 8 characters). Try again."
      echo
      p1=""; p2=""
      continue
    fi

    printf -v "$out_var" '%s' "$p1"
    p1=""; p2=""
    return 0
  done
}
