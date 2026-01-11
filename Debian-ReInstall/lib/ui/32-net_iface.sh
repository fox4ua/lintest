#!/usr/bin/env bash

# ui_pick_net_iface OUT_IFACE
# return: 0=Continue, 1=Cancel/ESC (exit), 2=Back
ui_pick_net_iface() {
  local out_iface="$1"
  local rc choice

  local -a items=()

  # Собираем интерфейсы кроме lo
  while IFS= read -r ifn; do
    [[ -n "$ifn" ]] || continue

    # state (UP/DOWN)
    local st mac
    st="$(cat "/sys/class/net/$ifn/operstate" 2>/dev/null || echo "?")"
    mac="$(cat "/sys/class/net/$ifn/address" 2>/dev/null || echo "-")"

    items+=("$ifn" "state=${st} mac=${mac}")
  done < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -v '^lo$' || true)

  if [[ ${#items[@]} -eq 0 ]]; then
    ui_msg "No network interfaces found (except lo)."
    return 1
  fi

  choice="$(
    ui_dialog dialog --clear --stdout \
      --title "Network interface" \
      --ok-label "Continue" \
      --cancel-label "Cancel" \
      --help-button --help-label "Back" \
      --menu "Select the network interface for installation:" 18 74 10 \
        "${items[@]}"
  )"
  rc=$?
  ui_clear

  case "$rc" in
    0) : ;;
    2) return 2 ;;
    1|255) return 1 ;;
    *) return 1 ;;
  esac

  # validate existence
  if [[ ! -d "/sys/class/net/$choice" ]]; then
    ui_msg "Interface not found: $choice"
    return 2
  fi

  printf -v "$out_iface" "%s" "$choice"
  return 0
}
