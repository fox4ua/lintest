#!/usr/bin/env bash

# Сообщения (можно вынести и в отдельный messages.sh, но можно оставить тут)
msg_nouefi=$'You selected UEFI, but this Rescue environment does NOT expose UEFI (/sys/firmware/efi is missing).\n\nOn many VPS this means UEFI boot may NOT be available, and the installed system could become unbootable.\n\nContinue forcing UEFI anyway?'
msg_uefi=$'You selected Legacy (BIOS/CSM), but this Rescue environment exposes UEFI.\n\nIf the VPS is configured to boot only in UEFI mode, Legacy installation may not boot.\n\nContinue forcing Legacy anyway?'

# окно предупреждения
# return: 0=Continue, 1=Cancel/ESC (exit), 2=Back
warn_mismatch_or_handle() {
  local text="$1"
  local rc
  ui_dialog dialog --clear \
    --title "Warning" \
    --yes-label "Continue" \
    --no-label "Cancel" \
    --help-button \
    --help-label "Back" \
    --yesno "$text" 12 74
  rc=$?
  ui_clear
  case "$rc" in
    0) return 0 ;;        # continue
    2) return 2 ;;        # back
    1|255) return 1 ;;    # cancel/ESC
    *) return 1 ;;
  esac
}
# окно выбора режима загрузки
# return: 0=Apply, 1=Cancel/ESC (exit), 2=Back (to welcome)
ui_pick_boot_mode() {
  local out_bootmode="$1"
  local out_label="$2"
  local has_uefi="${3:-0}"
  local choice rc

  while true; do
    choice="$(
      ui_dialog dialog --clear --stdout \
        --title "Boot mode" \
        --ok-label "Continue" \
        --cancel-label "Cancel" \
        --help-button \
        --help-label "Back" \
        --menu "Choose boot mode:" 13 74 6 \
          uefi    "UEFI + GPT" \
          biosgpt "Legacy BIOS + GPT" \
          biosmbr "Legacy BIOS + MBR"
    )"
    rc=$?
    ui_clear
    case "$rc" in
      0) : ;;
      2) return 2 ;;      # back -> welcome
      1|255) return 1 ;;  # cancel/ESC
      *) return 1 ;;
    esac

    # UEFI нет, но выбрали UEFI
    if [[ "$has_uefi" -eq 0 && "$choice" == "uefi" ]]; then
      warn_mismatch_or_handle "$msg_nouefi"
      case $? in
        0) : ;;          # continue
        2) continue ;;   # back
        *) return 1 ;;   # cancel/ESC
      esac
    fi
    # UEFI есть, но выбрали Legacy
    if [[ "$has_uefi" -eq 1 && "$choice" != "uefi" ]]; then
      warn_mismatch_or_handle "$msg_uefi"
      case $? in
        0) : ;;          # continue
        2) continue ;;   # back
        *) return 1 ;;   # cancel/ESC
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
