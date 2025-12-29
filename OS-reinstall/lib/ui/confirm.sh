#!/usr/bin/env bash

ui_confirm_or_exit() {
  dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Confirm" \
    --yes-label "Proceed" \
    --no-label "Cancel" \
    --yesno "Proceed with DISK WIPE and reinstall?" 8 60 || ui_abort
}
