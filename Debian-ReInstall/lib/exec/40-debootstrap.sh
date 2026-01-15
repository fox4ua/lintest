#!/usr/bin/env bash
# shellcheck shell=bash

# Runs debootstrap into TARGET_DIR.
#
# Requires variables:
#   TARGET_DIR
#   DEBIAN_SUITE          (e.g. bullseye/bookworm/trixie)
#   DEBIAN_MIRROR         (e.g. http://deb.debian.org/debian)
#   LOG_FILE
#
# Optional:
#   DEBIAN_ARCH           (default: dpkg --print-architecture)
#   DEBOOTSTRAP_VARIANT   (default: minbase)
#   DEBOOTSTRAP_INCLUDE   (comma-separated packages to include)
#   DEBOOTSTRAP_COMPONENTS (default: main)
#
# Exports:
#   TARGET_DIR (unchanged)

: "${DEBOOTSTRAP_VARIANT:=minbase}"
: "${DEBOOTSTRAP_COMPONENTS:=main}"

exec_debootstrap() {
  : "${TARGET_DIR:?TARGET_DIR is required}"
  : "${DEBIAN_SUITE:?DEBIAN_SUITE is required}"
  : "${DEBIAN_MIRROR:?DEBIAN_MIRROR is required}"
  : "${LOG_FILE:?LOG_FILE is required}"

  exec_require_tools debootstrap findmnt awk sed grep dpkg || return 1

  # Ensure target mounted
  if ! findmnt -rn "${TARGET_DIR}" >/dev/null 2>&1; then
    log "[!] debootstrap: TARGET_DIR is not mounted: ${TARGET_DIR}"
    ui_msg "Debootstrap requires mounted TARGET_DIR:\n${TARGET_DIR}\nLog: ${LOG_FILE}"
    return 1
  fi

  # Refuse to bootstrap into non-empty system (safety)
  if [[ -e "${TARGET_DIR}/bin/sh" || -e "${TARGET_DIR}/usr/bin/env" ]]; then
    log "[!] debootstrap: target already looks like a system: ${TARGET_DIR}"
    ui_msg "Target directory already contains a system:\n${TARGET_DIR}\n\nRefusing to run debootstrap.\nLog: ${LOG_FILE}"
    return 1
  fi

  # If https mirror, ensure CA bundle exists on host
  if [[ "${DEBIAN_MIRROR}" =~ ^https:// ]] && [[ ! -s /etc/ssl/certs/ca-certificates.crt ]]; then
    log "[!] debootstrap: https mirror but CA bundle missing on host"
    ui_msg "HTTPS mirror selected, but CA certificates are missing in rescue environment.\nInstall ca-certificates (host) or use http mirror.\nLog: ${LOG_FILE}"
    return 1
  fi

  local arch="${DEBIAN_ARCH:-$(dpkg --print-architecture)}"
  local include_args=()
  local comp_args=()

  if [[ -n "${DEBOOTSTRAP_INCLUDE:-}" ]]; then
    include_args=(--include="${DEBOOTSTRAP_INCLUDE}")
  fi
  if [[ -n "${DEBOOTSTRAP_COMPONENTS:-}" ]]; then
    comp_args=(--components="${DEBOOTSTRAP_COMPONENTS}")
  fi

  exec_progress 0 "Preparing debootstrap...\nSuite: ${DEBIAN_SUITE}\nMirror: ${DEBIAN_MIRROR}\nArch: ${arch}"

  # Quick mirror probe (best-effort; do not fail install on probe errors)
  exec_progress 10 "Probing mirror..."
  if command -v curl >/dev/null 2>&1; then
    exec_try curl -fsSI --max-time 10 "${DEBIAN_MIRROR%/}/dists/${DEBIAN_SUITE}/Release" >/dev/null
  elif command -v wget >/dev/null 2>&1; then
    exec_try wget -q --spider --timeout=10 "${DEBIAN_MIRROR%/}/dists/${DEBIAN_SUITE}/Release"
  else
    log "[!] debootstrap: no curl/wget for mirror probe (skipped)"
  fi

  exec_progress 20 "Running debootstrap (this can take a while)..."

  # Run debootstrap with output fully redirected to LOG_FILE to avoid "black screen".
  local cmd=(
    debootstrap
    --arch="${arch}"
    --variant="${DEBOOTSTRAP_VARIANT}"
    "${comp_args[@]}"
    "${include_args[@]}"
    "${DEBIAN_SUITE}"
    "${TARGET_DIR}"
    "${DEBIAN_MIRROR}"
  )

  log "[>] ${cmd[*]}"
  local rc=0
  {
    echo "----- debootstrap begin $(date -Is) -----"
    "${cmd[@]}" || rc=$?
    echo "----- debootstrap end $(date -Is) rc=${rc} -----"
  } >>"${LOG_FILE}" 2>&1

  if (( rc != 0 )); then
    log "[!] debootstrap: failed rc=${rc}"
    ui_msg "Debootstrap failed (rc=${rc}).\n\nLast log lines:\n$(tail -n 120 "${LOG_FILE}" 2>/dev/null || true)"
    return 1
  fi

  exec_progress 90 "Verifying base system..."
  if [[ ! -x "${TARGET_DIR}/bin/sh" ]]; then
    log "[!] debootstrap: /bin/sh missing after success?"
    ui_msg "Debootstrap finished, but target looks incomplete.\nLog: ${LOG_FILE}"
    return 1
  fi

  exec_progress 100 "Debootstrap completed."
  log "[=] debootstrap: OK suite=${DEBIAN_SUITE} arch=${arch} target=${TARGET_DIR}"
  return 0
}
