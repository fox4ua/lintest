#!/usr/bin/env bash

# ui_pick_boot_mode OUT_BOOTMODE OUT_LABEL HAS_UEFI
# return: 0=Apply(valid), 1=Cancel/ESC(exit), 2=Back(go welcome)
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
      0) : ;;          # OK -> проверяем выбор ниже
      2) return 2 ;;   # Back
      1|255) return 1 ;; # Cancel/ESC
      *) return 1 ;;
    esac

    # 1) Если UEFI недоступен, но выбрали UEFI -> warning и снова меню
    if [[ "$has_uefi" -eq 0 && "$choice" == "uefi" ]]; then
      ui_warn "UEFI не обнаружен в текущем окружении.\n\nСкорее всего вы загрузились в Legacy/BIOS режиме.\n\nВыберите Legacy BIOS или вернитесь назад."
      continue
    fi

    # 2) Если UEFI доступен, но выбрали Legacy -> warning и снова меню
    if [[ "$has_uefi" -eq 1 && "$choice" != "uefi" ]]; then
      ui_warn "В текущем окружении обнаружен UEFI.\n\nЕсли вы выберете Legacy BIOS, загрузчик может не установиться/не загрузиться.\n\nРекомендуется выбрать UEFI."
      continue
    fi

    # 3) Выбор валиден -> отдаём результат наружу
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
        # на всякий случай: вернёмся в меню
        continue
        ;;
    esac

    return 0
  done
}
