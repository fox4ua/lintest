#!/usr/bin/env bash

# ui_pick_root_password OUT_PASS
# return: 0=Continue, 1=Cancel/ESC (exit), 2=Back
ui_pick_root_password() {
  local out_pass="$1"
  local rc p1 p2

  while true; do
    p1="$(
      ui_dialog dialog --clear --stdout \
        --title "Root password" \
        --ok-label "Continue" \
        --cancel-label "Cancel" \
        --help-button --help-label "Back" \
        --insecure \
        --passwordbox "Enter your password for root:" 10 74
    )"
    rc=$?
    ui_clear

    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac

    p2="$(
      ui_dialog dialog --clear --stdout \
        --title "Root password" \
        --ok-label "Continue" \
        --cancel-label "Cancel" \
        --help-button --help-label "Back" \
        --insecure \
        --passwordbox "Repeat your password for root:" 10 74
    )"
    rc=$?
    ui_clear

    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac

    if [[ -z "$p1" ]]; then
      p1="12345678"
    fi

    if [[ -z "$p2" ]]; then
      p2="12345678"
    fi

    if [[ "$p1" != "$p2" ]]; then
      ui_msg "The passwords do not match. Please re-enter them."
      continue
    fi

    # базовая минимальная проверка длины
    if (( ${#p1} < 8 )); then
      ui_msg "Password too short (minimum 8 characters)."
      continue
    fi

    printf -v "$out_pass" "%s" "$p1"
    return 0
  done
}
