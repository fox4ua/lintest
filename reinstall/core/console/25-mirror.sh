#!/usr/bin/env bash
set -Eeuo pipefail

# Выбор Debian mirror
# Возвраты:
#   0 -> выбран/введён mirror
#   1 -> Cancel
ui_pick_debian_mirror_console() {
  local out_var="$1"
  local default_mirror="http://deb.debian.org/debian"
  local ans mirror

  while true; do
    echo "Debian mirror:"
    echo "  1) Use default: ${default_mirror}"
    echo "  2) Enter custom mirror"
    echo "  0) Cancel"
    printf "Choose [1-2, 0=Cancel]: "
    read -r ans

    case "$ans" in
      0) return 1 ;;
      1)
        printf -v "$out_var" '%s' "$default_mirror"
        return 0
        ;;
      2)
        while true; do
          printf "Enter mirror URL (пример: http://mirror.example/debian): "
          read -r mirror

          [[ -n "$mirror" ]] || { echo "Mirror cannot be empty."; continue; }

          # Мини-валидация: http/https + без пробелов
          if [[ "$mirror" =~ ^https?://[^[:space:]]+$ ]]; then
            printf -v "$out_var" '%s' "$mirror"
            return 0
          fi

          echo "Invalid URL. Must start with http:// or https:// and contain no spaces."
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
