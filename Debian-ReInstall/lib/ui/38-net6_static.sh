#!/usr/bin/env bash

# ui_pick_net6_static OUT_ADDR OUT_GW OUT_DNS
# return: 0=Continue, 1=Cancel/ESC (exit), 2=Back
ui_pick_net6_static() {
  local out_addr="$1" out_gw="$2" out_dns="$3"

  local rc addr gw dns

  addr="${NET6_ADDR:-}"
  gw="${NET6_GW:-}"
  dns="${NET6_DNS:-}"

  # IPv6/CIDR
  while true; do
    addr="$(
      ui_dialog dialog --clear --stdout \
        --title "IPv6 (Static)" \
        --ok-label "Continue" \
        --cancel-label "Cancel" \
        --help-button --help-label "Back" \
        --inputbox "Enter the IPv6 address in CIDR format.\n\nExample: 2001:db8::10/64" 12 74 "$addr"
    )"
    rc=$?
    ui_clear
    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac

    addr="$(ui_trim "$addr")"
    if [[ -z "$addr" || "$addr" != */* || "$addr" != *:* ]]; then
      ui_msg "Incorrect IPv6/CIDR: $addr"
      continue
    fi
    local prefix
    prefix="${addr##*/}"
    if ! [[ "$prefix" =~ ^[0-9]{1,3}$ ]] || (( prefix < 0 || prefix > 128 )); then
      ui_msg "Incorrect mask IPv6 (0..128): $prefix"
      continue
    fi
    break
  done

  # Gateway
  while true; do
    gw="$(
      ui_dialog dialog --clear --stdout \
        --title "IPv6 (Static)" \
        --ok-label "Continue" \
        --cancel-label "Cancel" \
        --help-button --help-label "Back" \
        --inputbox "Enter IPv6 Gateway.\n\nExample: 2001:db8::1" 12 74 "$gw"
    )"
    rc=$?
    ui_clear
    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac

    gw="$(ui_trim "$gw")"
    if [[ -z "$gw" || "$gw" == */* || "$gw" != *:* ]]; then
      ui_msg "Incorrect IPv6 Gateway: $gw"
      continue
    fi
    break
  done

  # DNS (space-separated)
  while true; do
    dns="$(
      ui_dialog dialog --clear --stdout \
        --title "IPv6 (Static)" \
        --ok-label "Continue" \
        --cancel-label "Cancel" \
        --help-button --help-label "Back" \
        --inputbox "Enter DNS IPv6 server(s) separated by a space.\n\nExample: 2606:4700:4700::1111 2001:4860:4860::8888\nCan be left blank." 12 74 "$dns"
    )"
    rc=$?
    ui_clear
    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac

    dns="$(ui_trim "$dns")"
    if [[ -n "$dns" ]]; then
      local ip
      for ip in $dns; do
        if [[ "$ip" == */* || "$ip" != *:* ]]; then
          ui_msg "Incorrect DNS IPv6: $ip"
          continue 2
        fi
      done
    fi
    break
  done

  printf -v "$out_addr" "%s" "$addr"
  printf -v "$out_gw" "%s" "$gw"
  printf -v "$out_dns" "%s" "$dns"
  return 0
}
