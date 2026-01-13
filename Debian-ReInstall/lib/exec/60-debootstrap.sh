#!/usr/bin/env bash

debootstrap_install() {
  stage "debootstrap"

  mkdir -p "$TARGET_DIR"

  local arch
  arch="$(detect_arch)"
  [[ -n "$arch" ]] || fatal "Unable to detect target architecture for debootstrap"

  run debootstrap --arch "$arch" "$DEBIAN_SUITE" "$TARGET_DIR" "$DEBIAN_MIRROR"
}

write_sources_list() {
  stage "apt_sources"

  local comps
  case "$DEBIAN_SUITE" in
    bullseye)
      comps="main contrib non-free"
      ;;
    bookworm|trixie|*)
      comps="main contrib non-free non-free-firmware"
      ;;
  esac

  mkdir -p "$TARGET_DIR/etc/apt"
  cat >"$TARGET_DIR/etc/apt/sources.list" <<EOF
deb $DEBIAN_MIRROR $DEBIAN_SUITE $comps
deb $DEBIAN_MIRROR $DEBIAN_SUITE-updates $comps
deb http://security.debian.org/debian-security $DEBIAN_SUITE-security $comps
EOF
}
