#!/usr/bin/env bash

: "${EXEC_DIR:?}"

source "$EXEC_DIR/10-release.sh"

execute_install() {
  stage "execute"
  log "[=] execution started"

  if (( DISK_NEEDS_RELEASE )); then
    if (( DISK_RELEASE_APPROVED )); then
      exec_release_disk_resources "$DISK"
    else
      log "[!] disk requires release but user did not approve"
    fi
  fi

  ui_msg "Execution steps are not implemented yet."
}
