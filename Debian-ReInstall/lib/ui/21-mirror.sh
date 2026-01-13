#!/usr/bin/env bash

# ui_pick_mirror OUT_MIRROR
# return: 0=Continue, 1=Cancel/ESC (exit), 2=Back
ui_pick_mirror() {
  local out_mirror="$1"
  local rc choice mirror

  mirror="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"

  choice="$(
    ui_dialog dialog --clear --stdout \
      --title "Debian mirror" \
      --ok-label "Continue" \
      --cancel-label "Cancel" \
      --help-button --help-label "Back" \
      --menu "Select a Debian mirror:" 16 74 8 \
        "http://deb.debian.org/debian" "deb.debian.org (recommended)" \
        "http://ftp.debian.org/debian" "ftp.debian.org" \
        "http://mirror.yandex.ru/debian" "mirror.yandex.ru (if available)" \
        "http://ftp.ua.debian.org/debian" "ua.debian.org (if available)" \
        custom "Custom"
  )"
  rc=$?
  ui_clear

  case "$rc" in
    0) : ;;
    2) return 2 ;;
    1|255) return 1 ;;
    *) return 1 ;;
  esac

  if [[ "$choice" == "custom" ]]; then
    mirror="$(
      ui_dialog dialog --clear --stdout \
        --title "Debian mirror" \
        --ok-label "Continue" \
        --cancel-label "Cancel" \
        --help-button --help-label "Back" \
        --inputbox "Enter the URL of the Debian mirror (example: http://deb.debian.org/debian):" 10 74 "$mirror"
    )"
    rc=$?
    ui_clear

    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac
  else
    mirror="$choice"
  fi

  # базовая валидация
  if ! [[ "$mirror" =~ ^https?://[^[:space:]]+$ ]]; then
    ui_msg "Incorrect mirror URL:\n$mirror"
    return 2
  fi
  if ! mirror_probe_suite "$mirror" "${DEBIAN_SUITE:-}"; then
    ui_msg "The mirror is unavailable or does not contain the selected version Debian.\n\nSuite: ${DEBIAN_SUITE:-unknown}\nMirror: $mirror\n\n${MIRROR_PROBE_ERR:-}"
    return 2
  fi
  printf -v "$out_mirror" "%s" "$mirror"
  return 0
}
