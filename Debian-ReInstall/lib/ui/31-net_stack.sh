#!/usr/bin/env bash

# ui_pick_net_stack OUT_NET_STACK DEBIAN_VERSION DEBIAN_SUITE
# return: 0=Continue, 1=Cancel/ESC (exit), 2=Back
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

  msg="Select the network configuration system.\n\nDebian: ${deb_ver} (${deb_suite})\Recommended: ${recommended}\n\nnetworkd: /etc/systemd/network/*.network\nifupdown: /etc/network/interfaces"

  # Ставим курсор на рекомендованное (через порядок пунктов)
  if [[ "$recommended" == "networkd" ]]; then
    choice="$(
      ui_dialog dialog --clear --stdout \
        --title "Network stack" \
        --ok-label "Continue" \
        --cancel-label "Cancel" \
        --help-button --help-label "Back" \
        --menu "$msg" 18 74 6 \
          networkd "systemd-networkd (recommended for 12/13)" \
          ifupdown "ifupdown (legacy)"
    )"
  else
    choice="$(
      ui_dialog dialog --clear --stdout \
        --title "Network stack" \
        --ok-label "Continue" \
        --cancel-label "Cancel" \
        --help-button --help-label "Back" \
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
    *) ui_msg "Incorrect selection: $choice"; return 2 ;;
  esac

  printf -v "$out_stack" "%s" "$choice"
  return 0
}
