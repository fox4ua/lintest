#!/usr/bin/env bash

# return: 0=Apply, 1=Cancel, 2=Back
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
      --ok-label "Применить" \
      --cancel-label "Отмена" \
      --extra-button \
      --extra-label "Назад" \
      --menu "Выберите схему:" 13 74 6 \
        uefi    "UEFI + GPT" \
        biosgpt "Legacy BIOS + GPT" \
        biosmbr "Legacy BIOS + MBR"
  )"
  rc=$?
  ((had_errexit)) && set -e

  ui_clear

  case "$rc" in
    0)
      case "$choice" in
        uefi)    printf -v "$out_bootmode" "uefi";    printf -v "$out_label" "UEFI + GPT";;
        biosgpt) printf -v "$out_bootmode" "biosgpt"; printf -v "$out_label" "BIOS + GPT";;
        biosmbr) printf -v "$out_bootmode" "biosmbr"; printf -v "$out_label" "BIOS + MBR";;
      esac
      return 0
      ;;
    3) return 2 ;;
    *) return 1 ;;
  esac
}
