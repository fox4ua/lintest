#!/usr/bin/env bash

# ui_pick_root_password OUT_PASS
# return: 0=ok, 1=cancel/esc, 2=back
ui_pick_root_password() {
  local out_pass="$1"
  local rc p1 p2

  while true; do
    p1="$(
      ui_dialog dialog --clear --stdout \
        --title "Root password" \
        --ok-label "Далее" \
        --cancel-label "Отмена" \
        --help-button --help-label "Назад" \
        --insecure \
        --passwordbox "Введите пароль для root:" 10 74
    )"
    rc=$?
    ui_clear

    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac

    p2="$(
      ui_dialog dialog --clear --stdout \
        --title "Root password" \
        --ok-label "Готово" \
        --cancel-label "Отмена" \
        --help-button --help-label "Назад" \
        --insecure \
        --passwordbox "Повторите пароль для root:" 10 74
    )"
    rc=$?
    ui_clear

    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac

    if [[ -z "$p1" ]]; then
      ui_msg "Пароль не может быть пустым."
      continue
    fi

    if [[ "$p1" != "$p2" ]]; then
      ui_msg "Пароли не совпадают. Повторите ввод."
      continue
    fi

    # базовая минимальная проверка длины
    if (( ${#p1} < 8 )); then
      ui_msg "Слишком короткий пароль (минимум 8 символов)."
      continue
    fi

    printf -v "$out_pass" "%s" "$p1"
    return 0
  done
}
