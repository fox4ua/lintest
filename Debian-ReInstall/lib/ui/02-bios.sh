#!/usr/bin/env bash

# ui_pick_boot_mode OUT_BOOTMODE OUT_LABEL
# return: 0=Apply, 1=Cancel/ESC, 2=Back
ui_pick_boot_mode() {
  local out_bootmode="$1"
  local out_label="$2"

  local choice rc
  choice="$(
    ui_dialog dialog --clear --stdout \
      --title "Режим загрузки" \
      --ok-label "Применить" \
      --cancel-label "Отмена" \
      --help-button \
      --help-label "Назад" \
      --menu "Выберите схему загрузки и разметки:" 13 74 6 \
        uefi    "UEFI + GPT" \
        biosgpt "Legacy BIOS + GPT" \
        biosmbr "Legacy BIOS + MBR"
  )"
  rc=$?

  ui_clear

  case "$rc" in
    0)
      case "$choice" in
        uefi)    printf -v "$out_bootmode" "%s" "uefi";    printf -v "$out_label" "%s" "UEFI + GPT" ;;
        biosgpt) printf -v "$out_bootmode" "%s" "biosgpt"; printf -v "$out_label" "%s" "Legacy BIOS + GPT" ;;
        biosmbr) printf -v "$out_bootmode" "%s" "biosmbr"; printf -v "$out_label" "%s" "Legacy BIOS + MBR" ;;
        *) return 1 ;;
      esac
      return 0
      ;;
    2)   return 2 ;;      # Back (Help)
    1|255) return 1 ;;    # Cancel/ESC
    *)   return 1 ;;
  esac
}
