#!/usr/bin/env bash

# ui_pick_net_iface OUT_IFACE
# return: 0=ok, 1=cancel/esc, 2=back
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
    ui_msg "Не найдено сетевых интерфейсов (кроме lo)."
    return 1
  fi

  choice="$(
    ui_dialog dialog --clear --stdout \
      --title "Network interface" \
      --ok-label "Далее" \
      --cancel-label "Отмена" \
      --help-button --help-label "Назад" \
      --menu "Выберите сетевой интерфейс для установки:" 18 74 10 \
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
    ui_msg "Интерфейс не найден: $choice"
    return 2
  fi

  printf -v "$out_iface" "%s" "$choice"
  return 0
}
