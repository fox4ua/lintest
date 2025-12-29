#!/usr/bin/env bash

ui_pick_boot_mode() {
  local msg
  msg=$(cat <<EOF

RUN ONLY IN RESCUE MODE.

All data will be destroyed.

Log: ${LOG_FILE}

EOF
  )

  dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Welcome" \
    --no-collapse --cr-wrap \
    --yes-label "Continue" \
    --no-label "Cancel" \
    --yesno "$msg" 12 74 || ui_abor
}
