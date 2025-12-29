#!/usr/bin/env bash

ui_welcome() {
  dialog --clear \
    --title "Debian Installer (debootstrap)" \
    --ok-label "Продолжить" \
    --cancel-label "Отмена" \
    --yesno "Этот мастер установит Debian через debootstrap.\n\nВНИМАНИЕ: данные на выбранном диске будут уничтожены.\n\nПродолжить?" 12 74
  local rc=$?
  ui_clear
  return "$rc"   # 0=OK, 1=Cancel, 255=ESC
}
