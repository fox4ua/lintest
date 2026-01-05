#!/usr/bin/env bash

# ui_pick_debian_version OUT_VERSION OUT_SUITE
# return: 0=ok, 1=cancel/esc, 2=back
ui_pick_debian_version() {
  local out_ver="$1"
  local out_suite="$2"

  local rc choice ver suite

  choice="$(
    ui_dialog dialog --clear --stdout \
      --title "Debian" \
      --ok-label "Далее" \
      --cancel-label "Отмена" \
      --help-button --help-label "Назад" \
      --menu "Выберите версию Debian для установки:" 14 74 6 \
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
    *)  ui_msg "Некорректный выбор Debian: $ver"; return 2 ;;
  esac

  printf -v "$out_ver" "%s" "$ver"
  printf -v "$out_suite" "%s" "$suite"
  return 0
}
