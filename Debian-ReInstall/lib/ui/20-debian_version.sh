#!/usr/bin/env bash

# ui_pick_debian_version OUT_VERSION OUT_SUITE
# return: 0=Continue, 1=Cancel/ESC (exit), 2=Back
ui_pick_debian_version() {
  local out_ver="$1"
  local out_suite="$2"

  local rc choice ver suite

  choice="$(
    ui_dialog dialog --clear --stdout \
      --title "Debian" \
      --ok-label "Continue" \
      --cancel-label "Cancel" \
      --help-button --help-label "Back" \
      --menu "Select the Debian version to install:" 14 74 6 \
        11 "Debian 11 (bullseye)" \
        12 "Debian 12 (bookworm)" \
        13 "Debian 13 (trixie)"
  )"
  rc=$?
  ui_clear

  case "$rc" in
    0) : ;;
    2) return 2 ;;
    1|255) return 1 ;;
    *) return 1 ;;
  esac

  ver="$choice"
  case "$ver" in
    11) suite="bullseye" ;;
    12) suite="bookworm" ;;
    13) suite="trixie" ;;
    *)  ui_msg "Incorrect selection Debian: $ver"; return 2 ;;
  esac

  printf -v "$out_ver" "%s" "$ver"
  printf -v "$out_suite" "%s" "$suite"
  return 0
}
