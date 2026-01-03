#!/usr/bin/env bash

# ui_pick_mirror OUT_MIRROR
# return: 0=ok, 1=cancel/esc, 2=back
ui_pick_mirror() {
  local out_mirror="$1"
  local rc choice mirror

  mirror="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"

  choice="$(
    ui_dialog dialog --clear --stdout \
      --title "Debian mirror" \
      --ok-label "Далее" \
      --cancel-label "Отмена" \
      --help-button --help-label "Назад" \
      --menu "Выберите зеркало Debian:" 16 74 8 \
        "http://deb.debian.org/debian" "deb.debian.org (рекомендуется)" \
        "http://ftp.debian.org/debian" "ftp.debian.org" \
        "http://mirror.yandex.ru/debian" "mirror.yandex.ru (если доступен)" \
        "http://ftp.ua.debian.org/debian" "ua.debian.org (если доступен)" \
        custom "Ввести вручную"
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
        --ok-label "Далее" \
        --cancel-label "Отмена" \
        --help-button --help-label "Назад" \
        --inputbox "Введите URL зеркала Debian (пример: http://deb.debian.org/debian):" 10 74 "$mirror"
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
    ui_msg "Некорректный URL зеркала:\n$mirror"
    return 2
  fi

  printf -v "$out_mirror" "%s" "$mirror"
  return 0
}
