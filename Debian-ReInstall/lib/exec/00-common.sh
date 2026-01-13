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

net_try_ping() {
  # Usage: net_try_ping <target> [tries] [timeout_sec]
  local target="${1:-}"
  local tries="${2:-3}"
  local to="${3:-2}"

  require_cmd ping || return 2

  local i
  for ((i=1; i<=tries; i++)); do
    if ping -c1 -W"$to" "$target" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

net_try_tcp() {
  # Usage: net_try_tcp <ip_or_host> <port> [timeout_sec]
  local host="${1:-}"
  local port="${2:-}"
  local to="${3:-3}"

  # bash /dev/tcp (fallback when ping is unavailable/blocked)
  timeout "$to" bash -c "cat </dev/null >/dev/tcp/$host/$port" >/dev/null 2>&1
}

exec_net_check_host() {
  stage "net_check"

  local ip_test="8.8.8.8"
  local host_test="google.com"

  log "[=] host connectivity check: ping $ip_test and ping $host_test"

  # 1) Internet reachability (IP)
  local ip_ok=0
  if net_try_ping "$ip_test" 3 2; then
    ip_ok=1
    log "[+] ping $ip_test OK"
  else
    log "[!] ping $ip_test failed; trying TCP check to $ip_test:53"
    if net_try_tcp "$ip_test" 53 3; then
      ip_ok=1
      log "[+] TCP $ip_test:53 OK (ICMP may be blocked)"
    fi
  fi

  if [[ "$ip_ok" != "1" ]]; then
    log "[!] No external connectivity."
    run ip -br addr || true
    run ip route || true
    run cat /etc/resolv.conf || true
    fatal "No internet connectivity: cannot reach $ip_test (ping and TCP:53 failed)."
  fi

  # 2) DNS resolution check
  if getent hosts "$host_test" >/dev/null 2>&1; then
    log "[+] DNS resolve $host_test OK"
  else
    log "[!] DNS resolve $host_test FAILED"
    run cat /etc/resolv.conf || true
    fatal "DNS is not working on host: cannot resolve $host_test (check /etc/resolv.conf)."
  fi

  # 3) Optional: ping hostname (may fail if ICMP blocked; do not hard-fail)
  if net_try_ping "$host_test" 2 2; then
    log "[+] ping $host_test OK"
  else
    log "[!] ping $host_test failed (ICMP may be blocked). DNS works, continuing."
  fi
}

write_target_resolv_conf_from_host() {
  # копируем "реальный" resolv.conf хоста (не stub) в target как обычный файл
  local src="/etc/resolv.conf"
  [[ -f /run/systemd/resolve/resolv.conf ]] && src="/run/systemd/resolve/resolv.conf"
  [[ -f /run/NetworkManager/resolv.conf ]] && src="/run/NetworkManager/resolv.conf"

  rm -f "$TARGET_DIR/etc/resolv.conf"
  install -m 0644 "$src" "$TARGET_DIR/etc/resolv.conf"
}

ensure_target_nsswitch_dns() {
  # если hosts: без dns — DNS в chroot может не работать
  local f="$TARGET_DIR/etc/nsswitch.conf"
  if [[ ! -f "$f" ]]; then
    cat >"$f" <<'EOF'
passwd:         files
group:          files
shadow:         files

hosts:          files dns
networks:       files

protocols:      db files
services:       db files
ethers:         db files
rpc:            db files
EOF
    return 0
  fi
  if ! grep -qE '^hosts:.*\sdns(\s|$)' "$f"; then
    sed -i 's/^hosts:.*/hosts:          files dns/' "$f"
  fi
}

chroot_has_cmd() {
  local cmd="$1"
  chroot "$TARGET_DIR" /bin/bash -lc "command -v $cmd" >/dev/null 2>&1
}

exec_net_check_target() {
  local prev_stage="${STAGE:-}"

  stage "net_check_target"
  log "[=] target(chroot) DNS/connectivity check"

  write_target_resolv_conf_from_host
  ensure_target_nsswitch_dns

  # Проверяем резолв в тех же условиях, что и apt (env -i через chroot_run*)
  if ! chroot_run_quiet "getent hosts deb.debian.org >/dev/null"; then
    log "[!] chroot DNS failed for deb.debian.org; fallback resolv.conf"
    write_resolv_conf_defaults
    chroot_run_quiet "getent hosts deb.debian.org >/dev/null" || fatal "DNS in chroot broken (deb.debian.org)"
  fi

  if ! chroot_run_quiet "getent hosts security.debian.org >/dev/null"; then
    log "[!] chroot DNS failed for security.debian.org; fallback resolv.conf"
    write_resolv_conf_defaults
    chroot_run_quiet "getent hosts security.debian.org >/dev/null" || fatal "DNS in chroot broken (security.debian.org)"
  fi

  # (опционально) ping IP — не про DNS
  chroot_run_quiet "ping -c1 -W2 8.8.8.8 >/dev/null" && log "[+] chroot ping 8.8.8.8 OK" || true

  # вернуть прежнюю стадию, чтобы apt логировался как [apt_install]
  STAGE="$prev_stage"
}

