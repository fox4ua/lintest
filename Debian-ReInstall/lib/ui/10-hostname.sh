#!/usr/bin/env bash

# ui_pick_hostname OUT_HOSTNAME_SHORT
# return: 0=ok, 1=cancel/esc, 2=back
ui_pick_hostname() {
  local out_var="$1"
  local rc val

  val="${HOSTNAME_SHORT:-debian}"

  val="$(
    ui_dialog dialog --clear --stdout \
      --title "Hostname" \
      --ok-label "Далее" \
      --cancel-label "Отмена" \
      --help-button --help-label "Назад" \
      --inputbox "Введите hostname (короткое имя, без точек).\n\nПример: pve, debian, node1" 12 74 "$val"
  )"
  rc=$?
  ui_clear

  case "$rc" in
    0) : ;;
    2) return 2 ;;
    1|255) return 1 ;;
    *) return 1 ;;
  esac

  # trim
  val="$(echo "$val" | awk '{$1=$1;print}')"

  # validation: RFC-ish label: 1..63, starts/ends alnum, inside alnum or '-'
  if ! [[ "$val" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]; then
    ui_msg "Некорректный hostname: $val\n\nПравило: без точек, 1..63 символов, буквы/цифры/дефис, не начинать/заканчивать дефисом."
    return 2
  fi

  printf -v "$out_var" "%s" "$val"
  return 0
}
