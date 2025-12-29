#!/usr/bin/env bash
set -euo pipefail
umask 077

REPO_OWNER="fox4ua"
REPO_NAME="lintest"
BRANCH="main"
SUBDIR="OS-reinstall"

DEST_DIR="/root/${SUBDIR}"
TARBALL_URL="https://codeload.github.com/${REPO_OWNER}/${REPO_NAME}/tar.gz/refs/heads/${BRANCH}"

die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run as root."
}

have() { command -v "$1" >/dev/null 2>&1; }

apt_install_if_missing() {
  local pkgs=()
  for p in "$@"; do
    dpkg -s "$p" >/dev/null 2>&1 || pkgs+=("$p")
  done
  if ((${#pkgs[@]})); then
    have apt-get || die "apt-get not found; install: ${pkgs[*]} manually."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y "${pkgs[@]}"
  fi
}

main() {
  need_root

  # Ensure basic tools exist (Debian rescue friendly)
  if have apt-get; then
    apt_install_if_missing ca-certificates curl tar gzip coreutils
    update-ca-certificates >/dev/null 2>&1 || true
  else
    have curl || die "curl not found."
    have tar  || die "tar not found."
  fi

  # Backup existing directory (idempotent)
  if [[ -d "$DEST_DIR" ]]; then
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    mv -f "$DEST_DIR" "${DEST_DIR}.bak.${ts}"
  fi
  mkdir -p "$DEST_DIR"

  local tmp tgz topdir srcdir
  tmp="$(mktemp -d)"
  tgz="${tmp}/repo.tgz"
  trap 'rm -rf "$tmp"' EXIT

  echo "[+] Downloading ${TARBALL_URL}"
  curl -fsSL "$TARBALL_URL" -o "$tgz"

  echo "[+] Extracting"
  tar -xzf "$tgz" -C "$tmp"

  topdir="$(find "$tmp" -maxdepth 1 -type d -name "${REPO_NAME}-*" | head -n 1 || true)"
  [[ -n "$topdir" ]] || die "Could not locate extracted repo directory."
  srcdir="${topdir}/${SUBDIR}"
  [[ -d "$srcdir" ]] || die "Directory not found in repo: ${SUBDIR}"

  cp -a "${srcdir}/." "$DEST_DIR/"

  # Permissions
  [[ -f "$DEST_DIR/install.sh" ]] || die "install.sh not found in ${DEST_DIR}"
  chmod 0700 "$DEST_DIR/install.sh"
  if [[ -d "$DEST_DIR/lib" ]]; then
    find "$DEST_DIR/lib" -type f -name '*.sh' -exec chmod 0700 {} +
  fi

  echo "[+] Running installer: ${DEST_DIR}/install.sh"
  cd "$DEST_DIR"
  exec ./install.sh
}

main "$@"
