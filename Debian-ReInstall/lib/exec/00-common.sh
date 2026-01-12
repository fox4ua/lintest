#!/usr/bin/env bash

# Common helpers for execute phase.

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1
}

fatal() {
  local msg="$1"
  log "[!] $msg"
  ui_msg "$msg\n\nLog: $LOG_FILE"
  exit 1
}

run() {
  # Usage: run <cmd> [args...]
  log "[>] $*"
  "$@" >>"$LOG_FILE" 2>&1
}

run_quiet() {
  "$@" >>"$LOG_FILE" 2>&1
}

part_path() {
  # nvme0n1p1 vs sda1
  local disk="$1" idx="$2"
  if [[ "$disk" =~ nvme[0-9]+n[0-9]+$ ]]; then
    printf '%sp%s' "$disk" "$idx"
  else
    printf '%s%s' "$disk" "$idx"
  fi
}

exec_install_deps() {
  # Best-effort deps install (Debian/Ubuntu rescue). Fails if critical commands are still missing.
  local -a required=(
    parted sfdisk wipefs blkid mkfs.ext4 mkswap chroot debootstrap
  )

  if [[ "${BOOT_MODE:-}" == "uefi" ]]; then
    required+=(mkfs.vfat)
  fi
  if [[ "${LVM_MODE:-none}" != "none" ]]; then
    required+=(pvcreate vgcreate lvcreate vgchange pvs vgs)
  fi

  local -a missing=()
  local c
  for c in "${required[@]}"; do
    require_cmd "$c" || missing+=("$c")
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  if ! require_cmd apt-get; then
    fatal "Missing required commands: ${missing[*]}. apt-get is not available to install them."
  fi

  export DEBIAN_FRONTEND=noninteractive
  run apt-get update || fatal "apt-get update failed (no network / broken mirror?)."

  local -a pkgs=()
  local add_pkg
  add_pkg() {
    local p="$1" e
    for e in "${pkgs[@]}"; do [[ "$e" == "$p" ]] && return 0; done
    pkgs+=("$p")
  }

  for c in "${missing[@]}"; do
    case "$c" in
      parted) add_pkg parted ;;
      sfdisk|wipefs|blkid|mkswap) add_pkg util-linux ;;
      mkfs.ext4) add_pkg e2fsprogs ;;
      mkfs.vfat) add_pkg dosfstools ;;
      debootstrap) add_pkg debootstrap ;;
      # grub-* are installed inside the target; host grub is not required
      pvcreate|vgcreate|lvcreate|vgchange|pvs|vgs) add_pkg lvm2 ;;
    esac
  done

  if [[ ${#pkgs[@]} -gt 0 ]]; then
    run apt-get install -y --no-install-recommends "${pkgs[@]}" || fatal "Failed to install required packages: ${pkgs[*]}"
  fi

  missing=()
  for c in "${required[@]}"; do
    require_cmd "$c" || missing+=("$c")
  done
  [[ ${#missing[@]} -eq 0 ]] || fatal "Still missing required commands: ${missing[*]}"
}

mount_chroot_helpers() {
  # Bind mounts for chroot usage
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
  # Reverse order, ignore failures
  run_quiet umount -R "$TARGET_DIR/run" || true
  run_quiet umount -R "$TARGET_DIR/dev/pts" || true
  run_quiet umount -R "$TARGET_DIR/dev" || true
  run_quiet umount -R "$TARGET_DIR/proc" || true
  run_quiet umount -R "$TARGET_DIR/sys" || true
}

chroot_run() {
  # Usage: chroot_run <command...>
  log "[chroot] $*"
  chroot "$TARGET_DIR" /usr/bin/env -i \
    HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    DEBIAN_FRONTEND=noninteractive \
    bash -lc "$*" >>"$LOG_FILE" 2>&1
}
chroot_run_quiet() {
  # Usage: chroot_run_quiet <command...> (no logging, for secrets)
  chroot "$TARGET_DIR" /usr/bin/env -i \
    HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    DEBIAN_FRONTEND=noninteractive \
    bash -lc "$*" >>"$LOG_FILE" 2>&1
}