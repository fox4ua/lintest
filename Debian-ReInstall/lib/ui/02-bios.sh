#!/usr/bin/env bash

# ui_pick_boot_mode OUT_BOOTMODE OUT_LABEL HAS_UEFI
# return: 0=Apply (accepted), 1=Cancel/ESC (exit), 2=Back (to welcome)
ui_pick_boot_mode() {
  local out_bootmode="$1"
  local out_label="$2"
  local has_uefi="${3:-0}"

  local choice rc warn_rc

  while true; do
    # Основное меню выбора режима
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
      0) : ;;            # OK -> дальше проверяем mismatch
      2) return 2 ;;     # Back -> предыдущее окно (welcome)
      1|255) return 1 ;; # Cancel/ESC -> выход
      *) return 1 ;;
    esac

    # mismatch #1: UEFI нет, но выбрали UEFI
    if [[ "$has_uefi" -eq 0 && "$choice" == "uefi" ]]; then
      ui_dialog dialog --clear \
        --title "Предупреждение" \
        --ok-label "Продолжить" \
        --cancel-label "Отмена" \
        --help-button \
        --help-label "Назад" \
        --yesno "UEFI не обнаружен в текущем окружении.\n\nЕсли продолжить с UEFI, система может не загрузиться.\n\nВыберите действие:" 12 74
      warn_rc=$?
      ui_clear

      case "$warn_rc" in
        0) : ;;            # Продолжить -> принять выбор
        2) continue ;;     # Назад -> обратно в меню выбора режима
        1|255) return 1 ;; # Отмена/ESC -> выход
        *) return 1 ;;
      esac
    fi

    # mismatch #2: UEFI есть, но выбрали Legacy
    if [[ "$has_uefi" -eq 1 && "$choice" != "uefi" ]]; then
      ui_dialog dialog --clear \
        --title "Предупреждение" \
        --ok-label "Продолжить" \
        --cancel-label "Отмена" \
        --help-button \
        --help-label "Назад" \
        --yesno "В текущем окружении обнаружен UEFI.\n\nЕсли продолжить с Legacy BIOS, загрузчик может установиться некорректно.\n\nВыберите действие:" 12 74
      warn_rc=$?
      ui_clear

      case "$warn_rc" in
        0) : ;;
        2) continue ;;
        1|255) return 1 ;;
        *) return 1 ;;
      esac
    fi

    # Принять выбор и отдать наружу
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
