#!/usr/bin/env bash

ui_welcome() {
  local msg
  msg=$'RUN ONLY IN RESCUE MODE.\n\nAll data will be destroyed.\n\nLog: '"${LOG_FILE}"$'\n'
  ui_dialog dialog --clear \
    --title "Debian Installer (debootstrap)" \
    --ok-label "Continue" \
    --cancel-label "Cancel" \
    --yesno "$msg" 12 74
  local rc=$?
  ui_clear
  return "$rc"  # 0=OK, 1=Cancel, 255=ESC
}
