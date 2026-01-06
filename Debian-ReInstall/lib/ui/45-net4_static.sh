#!/usr/bin/env bash

# ui_pick_net_static OUT_ADDR OUT_GW OUT_DNS
# return: 0=ok, 1=cancel/esc, 2=back
ui_pick_net_static() {
  local out_addr="$1"
  local out_gw="$2"
  local out_dns="$3"

  local rc addr gw dns

  addr="${NET_ADDR:-}"
  gw="${NET_GW:-}"
  dns="${NET_DNS:-}"

  # IP/CIDR
  addr="$(
    ui_dialog dialog --clear --stdout \
      --title "Network (Static)" \
      --ok-label "Далее" \
      --cancel-label "Отмена" \
      --help-button --help-label "Назад" \
      --inputbox "Введите IP в формате CIDR.\n\nПример: 192.168.1.10/24" 12 74 "$addr"
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
    ui_msg "Некорректный IP/CIDR: $addr"
    return 2
  fi
  # простая проверка октетов 0..255
  local o1 o2 o3 o4
  IFS='./' read -r o1 o2 o3 o4 _ <<<"$addr"
  if (( o1>255 || o2>255 || o3>255 || o4>255 )); then
    ui_msg "Некорректный IP: $addr"
    return 2
  fi

  # Gateway
  gw="$(
    ui_dialog dialog --clear --stdout \
      --title "Network (Static)" \
      --ok-label "Далее" \
      --cancel-label "Отмена" \
      --help-button --help-label "Назад" \
      --inputbox "Введите Gateway.\n\nПример: 192.168.1.1" 12 74 "$gw"
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
    ui_msg "Некорректный Gateway: $gw"
    return 2
  fi
  IFS='.' read -r o1 o2 o3 o4 <<<"$gw"
  if (( o1>255 || o2>255 || o3>255 || o4>255 )); then
    ui_msg "Некорректный Gateway: $gw"
    return 2
  fi

  # DNS (space-separated)
  dns="$(
    ui_dialog dialog --clear --stdout \
      --title "Network (Static)" \
      --ok-label "Готово" \
      --cancel-label "Отмена" \
      --help-button --help-label "Назад" \
      --inputbox "Введите DNS сервер(а) через пробел.\n\nПример: 1.1.1.1 8.8.8.8\nМожно оставить пустым." 12 74 "$dns"
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
        ui_msg "Некорректный DNS: $ip"
        return 2
      fi
      IFS='.' read -r o1 o2 o3 o4 <<<"$ip"
      if (( o1>255 || o2>255 || o3>255 || o4>255 )); then
        ui_msg "Некорректный DNS: $ip"
        return 2
      fi
    done
  fi

  printf -v "$out_addr" "%s" "$addr"
  printf -v "$out_gw" "%s" "$gw"
  printf -v "$out_dns" "%s" "$dns"
  return 0
}
