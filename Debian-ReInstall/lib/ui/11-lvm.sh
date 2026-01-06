#!/usr/bin/env bash

# ui_pick_lvm_mode OUT_LVM_MODE OUT_VG_NAME OUT_THINPOOL_NAME
# return: 0=Continue, 1=Cancel/ESC (exit), 2=Back
ui_pick_lvm_mode() {
  local out_mode="$1"
  local out_vg="$2"
  local out_thin="$3"

  local rc choice
  local mode="${LVM_MODE:-linear}"
  local vg="${VG_NAME:-pve}"
  local thin="${THINPOOL_NAME:-data}"

  choice="$(
    ui_dialog dialog --clear --stdout \
      --title "LVM" \
      --ok-label "Continue" \
      --cancel-label "Cancel" \
      --help-button --help-label "Back" \
      --menu "Select LVM mode (planning only):" 16 74 6 \
        linear "LVM Linear (VG + LV)" \
        thin   "LVM Thin (VG + thinpool + thin LV)" \
        none   "Without LVM (direct partitions)"
  )"
  rc=$?
  ui_clear

  case "$rc" in
    0) : ;;
    2) return 2 ;;
    1|255) return 1 ;;
    *) return 1 ;;
  esac

  mode="$choice"

  # Если LVM выключен — имена не нужны
  if [[ "$mode" == "none" ]]; then
    printf -v "$out_mode" "%s" "$mode"
    printf -v "$out_vg" "%s" ""
    printf -v "$out_thin" "%s" ""
    return 0
  fi

  # Имя VG (для linear и thin)
  while true; do
    vg="$(
      ui_dialog dialog --clear --stdout \
        --title "LVM" \
        --ok-label "Continue" \
        --cancel-label "Cancel" \
        --help-button --help-label "Back" \
        --inputbox "Enter the name of the Volume Group (VG):" 10 74 "$vg"
    )"
    rc=$?
    ui_clear
    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac

    # Валидация VG: допустимые символы
    if ! [[ "$vg" =~ ^[A-Za-z0-9+_.-]{1,32}$ ]]; then
      ui_msg "Incorrect name VG: $vg\n\nAllowable: A-Z a-z 0-9 + _ . - (1..32)"
      continue
    fi

    break
  done

  # thinpool имя нужно только для thin
  if [[ "$mode" == "thin" ]]; then
    while true; do
      thin="$(
        ui_dialog dialog --clear --stdout \
          --title "LVM Thin" \
          --ok-label "Continue" \
          --cancel-label "Cancel" \
          --help-button --help-label "Back" \
          --inputbox "Enter the name of the thinpool:" 10 74 "$thin"
      )"
      rc=$?
      ui_clear
      case "$rc" in
        0) : ;;
        2) return 2 ;;
        1|255) return 1 ;;
        *) return 1 ;;
      esac

      if ! [[ "$thin" =~ ^[A-Za-z0-9+_.-]{1,32}$ ]]; then
        ui_msg "Incorrect name thinpool: $thin\n\nAllowable: A-Z a-z 0-9 + _ . - (1..32)"
        continue
      fi

      break
    done
  else
    thin=""
  fi

  printf -v "$out_mode" "%s" "$mode"
  printf -v "$out_vg" "%s" "$vg"
  printf -v "$out_thin" "%s" "$thin"
  return 0
}
