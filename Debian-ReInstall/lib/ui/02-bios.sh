#!/usr/bin/env bash

# Глобальный флаг:
# UI_BACK=1  -> пользователь выбрал "Назад"
# UI_BACK=0  -> обычный выбор или Cancel
UI_BACK=0

# ui_pick_boot_mode OUT_BOOTMODE OUT_LABEL
# return: 0=выбор сделан, 1=Cancel/ESC
ui_pick_boot_mode() {
  local out_bootmode="$1"
  local out_label="$2"

  UI_BACK=0

  local choice rc
  set +e
  choice="$(
    dialog --clear --stdout \
      --title "Режим загрузки" \
      --ok-label "Выбрать" \
      --cancel-label "Отмена" \
      --menu "Выберите схему загрузки и разметки:" 14 74 7 \
        __back  "← Назад (к приветствию)" \
        uefi    "UEFI + GPT (EFI 512M FAT32)" \
        biosgpt "Legacy BIOS + GPT (bios_grub 1-2M)" \
        biosmbr "Legacy BIOS + MBR (msdos)"
  )"
  rc=$?
  set -e

  ui_clear

  # Cancel/ESC
  if [[ "$rc" -ne 0 ]]; then
    return 1
  fi

  # Back
  if [[ "$choice" == "__back" ]]; then
    UI_BACK=1
    return 0
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
      return 1
      ;;
  esac

  return 0
}
