#!/usr/bin/env bash

# ui_pick_net_mode OUT_NET_MODE
# return: 0=ok, 1=cancel/esc, 2=back
ui_pick_net_mode() {
  local out_mode="$1"
  local rc choice

  choice="$(
    ui_dialog dialog --clear --stdout \
      --title "Network" \
      --ok-label "Далее" \
      --cancel-label "Отмена" \
      --help-button --help-label "Назад" \
      --menu "Выберите режим настройки сети:" 13 74 5 \
        dhcp   "DHCP (получать адрес автоматически)" \
        static "Static (ввести IP вручную)"
  )"
  rc=$?
  ui_clear

  case "$rc" in
    0) : ;;
    2) return 2 ;;
    1|255) return 1 ;;
    *) return 1 ;;
  esac

  case "$choice" in
    dhcp|static) : ;;
    *) ui_msg "Некорректный выбор режима сети: $choice"; return 2 ;;
  esac

  printf -v "$out_mode" "%s" "$choice"
  return 0
}
