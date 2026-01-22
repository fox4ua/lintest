#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_debian_release_console() {
  local out_major_var="$1"
  local out_codename_var="$2"
  local ans

  while true; do
    echo "Debian release:"
    echo "  1) Debian 11 (bullseye)"
    echo "  2) Debian 12 (bookworm)"
    echo "  3) Debian 13 (trixie)"
    printf "Choose [1-3, 0=Cancel]: "
    read -r ans

    case "$ans" in
      0) return 1 ;;
      1)
        printf -v "$out_major_var" '%s' "11"
        printf -v "$out_codename_var" '%s' "bullseye"
        return 0
        ;;
      2)
        printf -v "$out_major_var" '%s' "12"
        printf -v "$out_codename_var" '%s' "bookworm"
        return 0
        ;;
      3)
        printf -v "$out_major_var" '%s' "13"
        printf -v "$out_codename_var" '%s' "trixie"
        return 0
        ;;
      *)
        echo "Invalid choice. Try again."
        ;;
    esac
  done
}
