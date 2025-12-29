#!/usr/bin/env bash

# ui_pick_boot_mode OUT_BOOTMODE OUT_LABEL
# return: 0=Apply, 1=Cancel/ESC (exit), 2=Back (go welcome)
ui_pick_boot_mode() {
  local out_bootmode="$1"
  local out_label="$2"

  local choice rc

  # Внутри функции отключаем -e на время dialog
  set +e
  choice="$(
    dialog --clear --stdout \
      --title "Режим загрузки" \
      --ok-label "Применить" \
      --cancel-label "Отмена" \
      --help-button \
      --help-label "Назад" \
      --menu "Выберите схему загрузки и разметки:" 13 74 6 \
        uefi    "UEFI + GPT (EFI 512M FAT32)" \
        biosgpt "Legacy BIOS + GPT (bios_grub 1-2M)" \
        biosmbr "Legacy BIOS + MBR (msdos)"
  )"
  rc=$?
  set -e

  ui_clear

  case "$rc" in
    0) # OK
      case "$choice" in
        uefi)    printf -v "$out_bootmode" "%s" "uefi";    printf -v "$out_label" "%s" "UEFI + GPT";;
        biosgpt) printf -v "$out_bootmode" "%s" "biosgpt"; printf -v "$out_label" "%s" "Legacy BIOS + GPT";;
        biosmbr) printf -v "$out_bootmode" "%s" "biosmbr"; printf -v "$out_label" "%s" "Legacy BIOS + MBR";;
        *) return 1;;
      esac
      return 0
      ;;
    2) # HELP button => Back
      return 2
      ;;
    1|255) # Cancel / ESC
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}
