#!/usr/bin/env bash

# ui_pick_root_size OUT_ROOT_GIB
# return: 0=ok, 1=cancel/esc, 2=back
ui_pick_root_size() {
  local out_root="$1"
  local rc=0
  local val="${ROOT_SIZE_GIB:-30}"

  val="$(
    ui_dialog dialog --clear --stdout \
      --title "root (/)" \
      --ok-label "Готово" \
      --cancel-label "Отмена" \
      --help-button --help-label "Назад" \
      --inputbox "Введите размер root в GiB.\n\n0 = занять всё остальное.\nРекомендуется: 30+\n\nПример: 30" 13 74 "$val"
  )"
  rc=$?
  ui_clear

  case "$rc" in
    0) : ;;
    2) return 2 ;;
    1|255) return 1 ;;
    *) return 1 ;;
  esac

  if ! [[ "$val" =~ ^[0-9]+$ ]]; then
    ui_msg "Некорректное значение root: $val\n\nНужно число (GiB)."
    return 2
  fi

  # 0 = остаток
  if (( val == 0 )); then
    printf -v "$out_root" "0"
    return 0
  fi

  # минимумы/максимумы
  if (( val < 10 || val > 8192 )); then
    ui_msg "Некорректный размер root: $val\n\nДопустимо: 10..8192 GiB или 0 (остаток)."
    return 2
  fi

  printf -v "$out_root" "%s" "$val"
  return 0
}
