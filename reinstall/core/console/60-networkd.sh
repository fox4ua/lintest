#!/usr/bin/env bash
set -Eeuo pipefail

ui_pick_networkd_console() {
  local out_var="$1"
  local ans
  local rec

  if [[ -z "${DEBIAN_MAJOR:-}" ]]; then
    echo "ERROR: DEBIAN_MAJOR is not set"
    return 1
  fi

  case "$DEBIAN_MAJOR" in
    11) rec="0" ;;  # ifupdown
    12|13) rec="1" ;; # networkd
    *) rec="1" ;;  # safe default
  esac

  while true; do
    echo "Network stack (--networkd)"
    echo "  2 = systemd-networkd"
    echo "  1 = ifupdown"
    echo "  Recommended for Debian ${DEBIAN_MAJOR}: ${rec}"
    echo "  Enter 0 to Cancel"
    printf "Use networkd [recommended=%s]: " "$rec"
    read -r ans

    case "$ans" in
      0) return 1 ;;
      "") ans="$rec" ;;
    esac

    case "$ans" in
      1|2)
        printf -v "$out_var" '%s' "$ans"
        return 0
        ;;
      *)
        echo "Invalid value. Use 1 or 2 (or 0 to cancel)."
        echo
        ;;
    esac
  done
}
