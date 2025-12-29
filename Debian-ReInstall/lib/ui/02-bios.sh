#!/usr/bin/env bash

# ui_pick_boot_mode OUT_BOOTMODE OUT_LABEL
# return: 0=Apply, 1=Cancel/ESC (exit), 2=Back (go welcome)
ui_pick_boot_mode() {
  local out_bootmode="$1"
  local out_label="$2"

  local had_errexit=0
  case $- in *e*) had_errexit=1;; esac

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
  ((had_errexit)) && set -e

  ui_clear

  # Cancel/ESC => выйти
  if [[ "$rc" -ne 0 ]]; then
    return 1
  fi

  # OK, но выбран Back => вернуться
  if [[ "$choice" == "__back" ]]; then
    return 2
  fi

  # OK, выбран режим
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
