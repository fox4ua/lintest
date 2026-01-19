#!/usr/bin/env bash

# ui_pick_hostname OUT_HOSTNAME_SHORT
# return: 0=Continue, 1=Cancel/ESC (exit), 2=Back
ui_pick_hostname() {
  local out_var="$1"
  local rc val

  val="${HOSTNAME_SHORT:-debian}"

  while true; do
    val="$(
      ui_dialog dialog --clear --stdout \
        --title "Hostname" \
        --ok-label "Continue" \
        --cancel-label "Cancel" \
        --help-button --help-label "Back" \
        --inputbox "Enter hostname (short name, without dots).\n\nExample: pve, debian, node1" 12 74 "$val"
    )"
    rc=$?
    ui_clear

    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac

    # trim
    val="$(ui_trim "$val")"

    # validation: 1..63, starts/ends alnum, inside alnum or '-'
    if ! [[ "$val" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]; then
      ui_msg "Incorrect hostname: $val\n\nRule: no dots, 1–63 characters, letters/numbers/hyphens, do not start/end with a hyphen."
      continue
    fi

    printf -v "$out_var" "%s" "$val"
    return 0
  done
}
