#!/usr/bin/env bash

# ui_pick_net_static OUT_ADDR OUT_GW OUT_DNS
# return: 0=Continue, 1=Cancel/ESC (exit), 2=Back
ui_pick_net4_static() {
  local out_addr="$1"
  local out_gw="$2"
  local out_dns="$3"

  local rc addr gw dns

  addr="${NET4_ADDR:-}"
  gw="${NET4_GW:-}"
  dns="${NET4_DNS:-}"

  # IP/CIDR
  while true; do
    addr="$(
      ui_dialog dialog --clear --stdout \
        --title "Network (Static)" \
        --ok-label "Continue" \
        --cancel-label "Cancel" \
        --help-button --help-label "Back" \
        --inputbox "Enter the IP address in CIDR format.\n\nExample: 192.168.1.10/24" 12 74 "$addr"
    )"
    rc=$?
    ui_clear
    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac

    addr="$(echo "$addr" | awk '{$1=$1;print}')"
    if ! [[ "$addr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$ ]]; then
      ui_msg "Incorrect IP/CIDR: $addr"
      continue
    fi
    # простая проверка октетов 0..255
    local o1 o2 o3 o4
    IFS='./' read -r o1 o2 o3 o4 _ <<<"$addr"
    if (( o1>255 || o2>255 || o3>255 || o4>255 )); then
      ui_msg "Incorrect IP: $addr"
      continue
    fi
    break
  done

  # Gateway
  while true; do
    gw="$(
      ui_dialog dialog --clear --stdout \
        --title "Network (Static)" \
        --ok-label "Continue" \
        --cancel-label "Cancel" \
        --help-button --help-label "Back" \
        --inputbox "Enter Gateway.\n\nExample: 192.168.1.1" 12 74 "$gw"
    )"
    rc=$?
    ui_clear
    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac

    gw="$(echo "$gw" | awk '{$1=$1;print}')"
    if ! [[ "$gw" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      ui_msg "Incorrect Gateway: $gw"
      continue
    fi
    IFS='.' read -r o1 o2 o3 o4 <<<"$gw"
    if (( o1>255 || o2>255 || o3>255 || o4>255 )); then
      ui_msg "Incorrect Gateway: $gw"
      continue
    fi
    break
  done

  # DNS (space-separated)
  while true; do
    dns="$(
      ui_dialog dialog --clear --stdout \
        --title "Network (Static)" \
        --ok-label "Continue" \
        --cancel-label "Cancel" \
        --help-button --help-label "Back" \
        --inputbox "Enter DNS server(s) separated by a space.\n\nExample: 1.1.1.1 8.8.8.8\nCan be left blank." 12 74 "$dns"
    )"
    rc=$?
    ui_clear
    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac

    dns="$(echo "$dns" | awk '{$1=$1;print}')"
    if [[ -n "$dns" ]]; then
      local ip
      for ip in $dns; do
        if ! [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
          ui_msg "Incorrect DNS: $ip"
          continue 2
        fi
        IFS='.' read -r o1 o2 o3 o4 <<<"$ip"
        if (( o1>255 || o2>255 || o3>255 || o4>255 )); then
          ui_msg "Incorrect DNS: $ip"
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
