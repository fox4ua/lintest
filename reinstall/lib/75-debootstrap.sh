#!/usr/bin/env bash
# shellcheck shell=bash

# Debootstrap stage wrapper.
# Requires: log(), die() from lib/00-log.sh
# Expects globals: ARCH, RELEASE, TARGET, MIRROR

debootstrap_run() {
  [[ -n "${TARGET:-}" ]] || die "TARGET is empty"
  [[ -d "${TARGET}" ]] || die "TARGET does not exist: ${TARGET}"
  [[ -n "${RELEASE:-}" ]] || die "RELEASE is empty"
  [[ -n "${MIRROR:-}" ]] || die "MIRROR is empty"
  [[ -n "${ARCH:-}" ]] || die "ARCH is empty"

  log "Running debootstrap..."
  debootstrap --arch="$ARCH" --variant=minbase "$RELEASE" "$TARGET" "$MIRROR"
}
