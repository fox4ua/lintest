#!/usr/bin/env bash
# shellcheck shell=bash

# Enables basic services (best-effort).
# Depends:
#   exec_in_chroot()

exec_services_enable() {
  : "${LOG_FILE:?}"
  exec_progress 0 "Enabling services (best-effort)..."

  exec_try exec_in_chroot systemctl enable ssh
  exec_try exec_in_chroot systemctl enable cron

  exec_progress 100 "Services step done."
  return 0
}
