#!/usr/bin/env bash

ui_welcome() {
  dialog --clear \
    --title "Debian Installer (debootstrap)" \
    --ok-label "Продолжить" \
    --cancel-label "Отмена" \
    --msgbox "Этот мастер установит Debian через debootstrap.\n\nВНИМАНИЕ: данные будут уничтожены.\n\nПродолжить?" 12 74
  local rc=$?
  ui_clear
  return "$rc"
}
