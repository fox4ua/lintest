#!/usr/bin/env bash
# shellcheck shell=bash

# Install packages in chroot via apt-get.
#
# Public:
#   exec_apt_install
#
# Requires variables:
#   TARGET_DIR
#   LOG_FILE
#
# Optional:
#   APT_PACKAGES          (space-separated packages to install)
#   APT_INSTALL_RECOMMENDS (1 to keep recommends, default: 0)
#   APT_UPDATE            (1 to run apt-get update, default: 1)

exec_apt_install() {
  : "${TARGET_DIR:?TARGET_DIR is required}"
  : "${LOG_FILE:?LOG_FILE is required}"

  exec_require_tools findmnt chroot || return 1

  if ! findmnt -rn "${TARGET_DIR}" >/dev/null 2>&1; then
    log "[!] apt_install: TARGET_DIR is not mounted: ${TARGET_DIR}"
    ui_msg "APT install requires mounted TARGET_DIR:\n${TARGET_DIR}\nLog: ${LOG_FILE}"
    return 1
  fi

  local packages_raw="${APT_PACKAGES:-}"
  if [[ -z "$packages_raw" ]]; then
    log "[=] apt_install: skipped (no packages configured)"
    exec_progress 100 "APT install skipped (no packages)."
    return 0
  fi

  local -a packages=()
  read -r -a packages <<<"$packages_raw"
  if [[ ${#packages[@]} -eq 0 ]]; then
    log "[=] apt_install: skipped (no packages parsed)"
    exec_progress 100 "APT install skipped (no packages)."
    return 0
  fi

  local update_lists="${APT_UPDATE:-1}"
  local recommends="${APT_INSTALL_RECOMMENDS:-0}"
  local -a apt_args=(install -y)
  if [[ "$recommends" != "1" ]]; then
    apt_args+=(--no-install-recommends)
  fi

  exec_progress 0 "Preparing apt install..."
  export DEBIAN_FRONTEND=noninteractive

  if [[ "$update_lists" == "1" ]]; then
    exec_progress 15 "Running apt-get update in chroot..."
    if ! exec_in_chroot apt-get update; then
      log "[!] apt_install: apt-get update failed"
      ui_msg "Apt update failed in chroot.\nLog: ${LOG_FILE}"
      return 1
    fi
  else
    log "[=] apt_install: apt-get update skipped"
  fi

  exec_progress 50 "Installing packages in chroot..."
  if ! exec_in_chroot apt-get "${apt_args[@]}" "${packages[@]}"; then
    log "[!] apt_install: apt-get install failed"
    ui_msg "Apt install failed in chroot.\nLog: ${LOG_FILE}"
    return 1
  fi

  exec_progress 85 "Cleaning apt cache..."
  if ! exec_in_chroot apt-get clean; then
    log "[!] apt_install: apt-get clean failed (ignored)"
  fi

  exec_progress 100 "APT install completed."
  log "[=] apt_install: OK packages=${packages[*]}"
  return 0
}
