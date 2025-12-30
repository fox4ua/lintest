#!/usr/bin/env bash

# ui_pick_boot_mode OUT_BOOTMODE OUT_LABEL HAS_UEFI
# return: 0=Apply(valid or forced), 1=Cancel/ESC(exit), 2=Back(go welcome)
ui_pick_boot_mode() {
  local out_bootmode="$1"
  local out_label="$2"
  local has_uefi="${3:-0}"

  local choice rc warn_rc

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
      2) return 2 ;;      # Back -> welcome
      1|255) return 1 ;;  # Cancel/ESC -> exit
      *) return 1 ;;
    esac

    # mismatch: HAS_UEFI=0, но выбрали UEFI
    if [[ "$has_uefi" -eq 0 && "$choice" == "uefi" ]]; then
      ui_warn "UEFI не обнаружен в текущем окружении.\n\nЕсли продолжить с UEFI, система может не загрузиться.\n\nЧто делаем?"
      warn_rc=$?
      case "$warn_rc" in
        0) : ;;          # Продолжить -> принимаем выбор
        2) continue ;;   # Назад -> снова меню
        1|255) return 1 ;; # Отмена
        *) return 1 ;;
      esac
    fi

    # mismatch: HAS_UEFI=1, но выбрали Legacy
    if [[ "$has_uefi" -eq 1 && "$choice" != "uefi" ]]; then
      ui_warn "В текущем окружении обнаружен UEFI.\n\nЕсли продолжить с Legacy BIOS, загрузчик может установиться некорректно.\n\nЧто делаем?"
      warn_rc=$?
      case "$warn_rc" in
        0) : ;;
        2) continue ;;
        1|255) return 1 ;;
        *) return 1 ;;
      esac
    fi

    # принять выбор
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
