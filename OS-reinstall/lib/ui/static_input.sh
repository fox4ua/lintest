#!/usr/bin/env bash

ui_input_static() {
  local profile="$1"

  local gw_def dns_def
  gw_def="$(ui_guess_default_gw)"
  dns_def="$(ui_guess_dns_list)"

  if [[ "$profile" == "ovh32" ]]; then
    local ip gw dns
    ip=$(dialog --clear \
      --backtitle "OVH VPS Rescue Installer" \
      --title "OVH static (/32)" \
      --inputbox "IPv4 address (no /32, e.g. 203.0.113.10):" 10 86 "" \
      3>&1 1>&2 2>&3) || ui_abort

    gw=$(dialog --clear \
      --backtitle "OVH VPS Rescue Installer" \
      --title "OVH static (/32)" \
      --inputbox "Gateway (suggested from Rescue default route):" 10 86 "${gw_def}" \
      3>&1 1>&2 2>&3) || ui_abort

    dns=$(dialog --clear \
      --backtitle "OVH VPS Rescue Installer" \
      --title "OVH static (/32)" \
      --inputbox "DNS (space separated; suggested from Rescue resolv.conf):" 10 92 "${dns_def}" \
      3>&1 1>&2 2>&3) || ui_abort

    echo "${ip}|${gw}|${dns}"
  else
    local ipcidr gw dns
    ipcidr=$(dialog --clear \
      --backtitle "OVH VPS Rescue Installer" \
      --title "Static IPv4" \
      --inputbox "IP/CIDR (e.g. 203.0.113.10/24):" 10 86 "" \
      3>&1 1>&2 2>&3) || ui_abort

    gw=$(dialog --clear \
      --backtitle "OVH VPS Rescue Installer" \
      --title "Static IPv4" \
      --inputbox "Gateway (suggested from Rescue default route):" 10 86 "${gw_def}" \
      3>&1 1>&2 2>&3) || ui_abort

    dns=$(dialog --clear \
      --backtitle "OVH VPS Rescue Installer" \
      --title "Static IPv4" \
      --inputbox "DNS (space separated; suggested from Rescue resolv.conf):" 10 92 "${dns_def}" \
      3>&1 1>&2 2>&3) || ui_abort

    echo "${ipcidr}|${gw}|${dns}"
  fi
}
