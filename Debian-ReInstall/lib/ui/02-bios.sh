#!/usr/bin/env bash

# Сообщения (можно вынести и в отдельный messages.sh, но можно оставить тут)
msg_nouefi=$'UEFI не обнаружен в текущем окружении.\n\nЕсли продолжить с UEFI, система может не загрузиться.\n\nВыберите действие:'
msg_uefi=$'В текущем окружении обнаружен UEFI.\n\nЕсли продолжить с Legacy BIOS, загрузчик может установиться некорректно.\n\nВыберите действие:'

# warn_mismatch_or_handle TEXT
# return:
#   0 -> Продолжить
#   2 -> Назад (вернуться в меню выбора режима)
#   1 -> Отмена/ESC (выйти из мастера)
warn_mismatch_or_handle() {
  local text="$1"
  local warn_rc

  ui_dialog dialog --clear \
    --title "Предупреждение" \
    --ok-label "Продолжить" \
    --cancel-label "Отмена" \
    --help-button \
    --help-label "Назад" \
    --yesno "$text" 12 74
  warn_rc=$?
  ui_clear

  case "$warn_rc" in
    0) return 0 ;;        # continue
    2) return 2 ;;        # back to menu
    1|255) return 1 ;;    # cancel/esc
    *) return 1 ;;
  esac
}

# ui_pick_boot_mode OUT_BOOTMODE OUT_LABEL HAS_UEFI
# return: 0=Apply (accepted), 1=Cancel/ESC (exit), 2=Back (to welcome)
ui_pick_boot_mode() {
  local out_bootmode="$1"
  local out_label="$2"
  local has_uefi="${3:-0}"

  local choice rc

  while true; do
    choice="$(
      ui_dialog dialog --clear --stdout \
        --title "Режим загрузки" \
        --ok-label "Применить" \
        --cancel-label "Отмена" \
        --help-button \
        --help-label "Назад" \
        --menu "Выберите режим загрузки:" 13 74 6 \
          uefi    "UEFI + GPT" \
          biosgpt "Legacy BIOS + GPT" \
          biosmbr "Legacy BIOS + MBR"
    )"
    rc=$?

    ui_clear

    case "$rc" in
      0) : ;;
      2) return 2 ;;      # back -> welcome
      1|255) return 1 ;;  # cancel/esc
      *) return 1 ;;
    esac

    # mismatch #1: UEFI нет, но выбрали UEFI
    if [[ "$has_uefi" -eq 0 && "$choice" == "uefi" ]]; then
      warn_mismatch_or_handle "$msg_nouefi"
      case $? in
        0) : ;;          # Продолжить -> принять выбор
        2) continue ;;   # Назад -> меню выбора режима
        *) return 1 ;;   # Отмена/ESC -> выход
      esac
    fi

    # mismatch #2: UEFI есть, но выбрали Legacy
    if [[ "$has_uefi" -eq 1 && "$choice" != "uefi" ]]; then
      warn_mismatch_or_handle "$msg_uefi"
      case $? in
        0) : ;;
        2) continue ;;
        *) return 1 ;;
      esac
    fi

    case "$choice" in
      uefi)
        printf -v "$out_bootmode" "%s" "uefi"
        printf -v "$out_label"    "%s" "UEFI + GPT"
        ;;
      biosgpt)
        printf -v "$out_bootmode" "%s" "biosgpt"
        printf -v "$out_label"    "%s" "Legacy BIOS + GPT"
        ;;
      biosmbr)
        printf -v "$out_bootmode" "%s" "biosmbr"
        printf -v "$out_label"    "%s" "Legacy BIOS + MBR"
        ;;
      *)
        continue
        ;;
    esac

    return 0
  done
}
