#!/usr/bin/env bash
set -Eeuo pipefail

preflight_reset_state() {
  stage_set "preflight"
  log "Reset state: unmount /mnt, swapoff, deactivate LVM, remove dm/kpartx maps"

  umount -R /mnt 2>/dev/null || true
  swapoff -a 2>/dev/null || true
  vgchange -an 2>/dev/null || true
  dmsetup remove_all 2>/dev/null || true

  for d in /dev/sd[a-z] /dev/vd[a-z] /dev/nvme*n*; do
    [[ -b "$d" ]] || continue
    kpartx -d "$d" 2>/dev/null || true
  done

  udevadm settle 2>/dev/null || true
}

preflight_check_rescue_mode_hint() {
  stage_set "preflight"
  local root_src root_fstype
  root_src="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
  root_fstype="$(findmnt -n -o FSTYPE / 2>/dev/null || true)"
  log "Rescue root: source=${root_src:-unknown} fstype=${root_fstype:-unknown}"
}

preflight_check_rescue_not_on_disk() {
  stage_set "preflight"
  local disk="$1"
  local root_src
  root_src="$(findmnt -n -o SOURCE / 2>/dev/null || true)"

  if [[ -n "$root_src" && "$root_src" == ${disk}* ]]; then
    die "Rescue root is on ${root_src}. Cannot wipe ${disk} in this rescue. Use RAM/network rescue."
  fi

  if findmnt -rn -o SOURCE,TARGET | awk '{print $1}' | grep -qE "^${disk}"; then
    warn "Some partitions from ${disk} are mounted:"
    findmnt -rn -o SOURCE,TARGET | awk -v d="$disk" '$1 ~ "^"d {print}' | tee -a "$LOG_FILE" || true
    die "Target disk has mounted partitions in rescue. Unmount them or reboot rescue, then retry."
  fi
}

preflight_check_time_dns() {
  stage_set "preflight"

  log "DNS check: resolving deb.debian.org"
  getent ahostsv4 deb.debian.org >/dev/null 2>&1 || die "DNS broken: cannot resolve deb.debian.org. Fix /etc/resolv.conf."

  log "Time sanity check (for TLS/apt)"
  local now
  now="$(date +%s)"
  if (( now < 1577836800 )); then
    warn "System time looks wrong (epoch=${now}). Trying ntpdate..."
    ntpdate -u pool.ntp.org 2>&1 | tee -a "$LOG_FILE" || die "Time sync failed. Fix time; apt/debootstrap may fail."
  fi
}

preflight_check_mirror() {
  stage_set "preflight"
  local mirror="$1" suite="$2"
  local url="${mirror%/}/dists/${suite}/Release"
  log "Mirror check: ${url}"
  curl -fsSI --max-time 12 "$url" >/dev/null || die "Mirror unreachable or suite missing: ${url}"
}

preflight_check_tools() {
  stage_set "preflight"
  command -v debootstrap >/dev/null 2>&1 || die "debootstrap missing"
  command -v parted >/dev/null 2>&1 || die "parted missing"
  log "Tool sanity OK"
}
