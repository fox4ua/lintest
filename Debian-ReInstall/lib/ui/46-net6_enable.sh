#!/usr/bin/env bash

# ui_pick_net6_enable OUT_ENABLE
# return: 0=ok, 1=cancel, 2=back
ui_pick_net6_enable() {
  local out="$1"
  local rc choice

  choice="$(
    ui_dialog dialog --clear --stdout \
      --title "IPv6" \
      --ok-label "Далее" \
      --cancel-label "Отмена" \
      --help-button --help-label "Назад" \
      --menu "Включить IPv6?" 12 60 4 \
        1 "Да (использовать IPv6)" \
        0 "Нет (IPv6 отключён)"
  )"
  rc=$?
  ui_clear

  case "$rc" in
    0) printf -v "$out" "%s" "$choice"; return 0 ;;
    2) return 2 ;;
    *) return 1 ;;
  esac
}
