#!/usr/bin/env bash

mount_chroot_helpers() {
  run mount --bind /dev "$TARGET_DIR/dev"
  run mount --bind /dev/pts "$TARGET_DIR/dev/pts"
  run mount --bind /proc "$TARGET_DIR/proc"
  run mount --bind /sys "$TARGET_DIR/sys"
  if [[ -d /run ]]; then
    mkdir -p "$TARGET_DIR/run"
    run mount --bind /run "$TARGET_DIR/run"
  fi
}

umount_chroot_helpers() {
  run_quiet umount -R "$TARGET_DIR/run" || true
  run_quiet umount -R "$TARGET_DIR/dev/pts" || true
  run_quiet umount -R "$TARGET_DIR/dev" || true
  run_quiet umount -R "$TARGET_DIR/proc" || true
  run_quiet umount -R "$TARGET_DIR/sys" || true
}

chroot_run() {
  log "[chroot] $*"
  chroot "$TARGET_DIR" /usr/bin/env -i \
    HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    DEBIAN_FRONTEND=noninteractive \
    bash -lc "$*" >>"$LOG_FILE" 2>&1
}

chroot_run_quiet() {
  chroot "$TARGET_DIR" /usr/bin/env -i \
    HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    DEBIAN_FRONTEND=noninteractive \
    bash -lc "$*" >>"$LOG_FILE" 2>&1
}

chroot_has_cmd() {
  local cmd="$1"
  chroot "$TARGET_DIR" /bin/bash -lc "command -v $cmd" >/dev/null 2>&1
}
