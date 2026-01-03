#!/usr/bin/env bash

# ui_pick_net_stack OUT_NET_STACK DEBIAN_VERSION DEBIAN_SUITE
# return: 0=ok, 1=cancel/esc, 2=back
ui_pick_net_stack() {
  local out_stack="$1"
  local deb_ver="$2"
  local deb_suite="$3"

  local rc choice recommended msg

  # Рекомендация:
  # 11 -> ifupdown (legacy привычно)
  # 12/13 -> networkd (современнее, проще в chroot)
  case "$deb_ver" in
    11) recommended="ifupdown" ;;
    12|13) recommended="networkd" ;;
    *) recommended="networkd" ;;
  esac

  msg="Выберите систему настройки сети.\n\nDebian: ${deb_ver} (${deb_suite})\nРекомендовано: ${recommended}\n\nnetworkd: /etc/systemd/network/*.network\nifupdown: /etc/network/interfaces"

  # Ставим курсор на рекомендованное (через порядок пунктов)
  if [[ "$recommended" == "networkd" ]]; then
    choice="$(
      ui_dialog dialog --clear --stdout \
        --title "Network stack" \
        --ok-label "Далее" \
        --cancel-label "Отмена" \
        --help-button --help-label "Назад" \
        --menu "$msg" 18 74 6 \
          networkd "systemd-networkd (recommended for 12/13)" \
          ifupdown "ifupdown (legacy)"
    )"
  else
    choice="$(
      ui_dialog dialog --clear --stdout \
        --title "Network stack" \
        --ok-label "Далее" \
        --cancel-label "Отмена" \
        --help-button --help-label "Назад" \
        --menu "$msg" 18 74 6 \
          ifupdown "ifupdown (recommended for 11)" \
          networkd "systemd-networkd"
    )"
  fi

  rc=$?
  ui_clear

  case "$rc" in
    0) : ;;
    2) return 2 ;;
    1|255) return 1 ;;
    *) return 1 ;;
  esac

  case "$choice" in
    networkd|ifupdown) : ;;
    *) ui_msg "Некорректный выбор: $choice"; return 2 ;;
  esac

  printf -v "$out_stack" "%s" "$choice"
  return 0
}
