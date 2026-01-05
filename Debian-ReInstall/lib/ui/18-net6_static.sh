#!/usr/bin/env bash

# ui_pick_net6_static ADDR GW DNS
# return: 0=ok, 1=cancel, 2=back
ui_pick_net6_static() {
  local o_addr="$1" o_gw="$2" o_dns="$3"
  local rc

  local addr gw dns
  addr="${NET6_ADDR:-}"
  gw="${NET6_GW:-}"
  dns="${NET6_DNS:-}"

  addr="$(
    ui_dialog dialog --clear --stdout \
      --title "IPv6 static" \
      --inputbox "IPv6 address (CIDR)\nExample: 2001:db8::10/64" 10 70 "$addr"
  )" || return 1
  ui_clear

  gw="$(
    ui_dialog dialog --clear --stdout \
      --title "IPv6 static" \
      --inputbox "Gateway IPv6\nExample: 2001:db8::1" 10 70 "$gw"
  )" || return 1
  ui_clear

  dns="$(
    ui_dialog dialog --clear --stdout \
      --title "IPv6 static" \
      --inputbox "DNS IPv6 (space separated)\nExample: 2606:4700:4700::1111" 10 70 "$dns"
  )" || return 1
  ui_clear

  printf -v "$o_addr" "%s" "$addr"
  printf -v "$o_gw" "%s" "$gw"
  printf -v "$o_dns" "%s" "$dns"
  return 0
}
