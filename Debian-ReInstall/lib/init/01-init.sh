#!/usr/bin/env bash
# Check root
require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Run this script as root (or via sudo)." >&2
    exit 1
  fi
}
