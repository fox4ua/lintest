#!/usr/bin/env bash

ui_welcome() {
  local msg
  msg=$(cat <<EOF

RUN ONLY IN RESCUE MODE.

All data will be destroyed.

Log: ${LOG_FILE}

EOF
  )
  ui_dialog dialog --clear \
    --title "Debian Installer (debootstrap)" \
    --ok-label "Continue" \
    --cancel-label "Cancel" \
    --yesno "$msg"12 74
  local rc=$?
  ui_clear
  return "$rc"   # 0=OK, 1=Cancel, 255=ESC
}
