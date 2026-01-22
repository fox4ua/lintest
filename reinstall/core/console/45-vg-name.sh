#!/usr/bin/env bash
set -Eeuo pipefail

# Выбор VG name (только для LVM/thin)
# Возвраты:
#   0 -> выбран VG_NAME
#   1 -> Cancel
ui_pick_vg_name_console() {
  local out_var="$1"
  local default_vg="vg0"
  local ans vg

  while true; do
    echo "LVM Volume Group name (--vg-name):"
    echo "  1) Use default: ${default_vg}"
    echo "  2) Enter custom VG name"
    echo "  0) Cancel"
    printf "Choose [1-2, 0=Cancel]: "
    read -r ans

    case "$ans" in
      0) return 1 ;;
      1)
        printf -v "$out_var" '%s' "$default_vg"
        return 0
        ;;
      2)
        while true; do
          printf "Enter VG name (пример: vg0, pve, data_vg): "
          read -r vg
          [[ -n "$vg" ]] || { echo "VG name cannot be empty."; continue; }

          # допустимы: буквы/цифры/._+- (без пробелов). Первый символ: буква/цифра/_
          if [[ "$vg" =~ ^[A-Za-z0-9_][A-Za-z0-9._+-]*$ ]]; then
            printf -v "$out_var" '%s' "$vg"
            return 0
          fi

          echo "Invalid VG name. Allowed: A-Z a-z 0-9 _ . + - (no spaces)."
          echo "  1) Try again"
          echo "  0) Cancel"
          printf "Choose [1, 0=Cancel]: "
          read -r ans
          [[ "$ans" == "0" ]] && return 1
        done
        ;;
      *)
        echo "Invalid choice. Try again."
        ;;
    esac
  done
}
