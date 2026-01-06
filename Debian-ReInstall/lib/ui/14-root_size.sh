#!/usr/bin/env bash

# ui_pick_root_size OUT_ROOT_GIB
# return: 0=Continue, 1=Cancel/ESC (exit), 2=Back
ui_pick_root_size() {
  local out_root="$1"
  local rc=0
  local val="${ROOT_SIZE_GIB:-30}"

  val="$(
    ui_dialog dialog --clear --stdout \
      --title "root (/)" \
      --ok-label "Continue" \
      --cancel-label "Cancel" \
      --help-button --help-label "Back" \
      --inputbox "Enter the root size in GiB.\n\n0 = use all remaining space.\nRecommended: 30+\n\nExample: 30" 13 74 "$val"
  )"
  rc=$?
  ui_clear

  case "$rc" in
    0) : ;;
    2) return 2 ;;
    1|255) return 1 ;;
    *) return 1 ;;
  esac

  if ! [[ "$val" =~ ^[0-9]+$ ]]; then
    ui_msg "Incorrect value root: $val\n\nNeed a number (GiB)."
    return 2
  fi

  # 0 = остаток
  if (( val == 0 )); then
    printf -v "$out_root" "%s" "0"
    return 0
  fi

  # минимумы/максимумы
  if (( val < 10 || val > 8192 )); then
    ui_msg "Incorrect root size: $val\n\nAllowed: 10..8192 GiB or 0 (remaining)."
    return 2
  fi

  printf -v "$out_root" "%s" "$val"
  return 0
}
