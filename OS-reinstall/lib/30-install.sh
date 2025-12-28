#!/usr/bin/env bash
set -Eeuo pipefail

components_for_suite() {
  case "$1" in
    bullseye) echo "main contrib non-free" ;;
    bookworm|trixie) echo "main contrib non-free non-free-firmware" ;;
    *) echo "main contrib non-free non-free-firmware" ;;
  esac
}

write_sources_list() {
  local root="$1" suite="$2" mirror="$3"
  local comps; comps="$(components_for_suite "$suite")"

  mkdir -p "${root}/etc/apt"

  cat > "${root}/etc/apt/sources.list" <<EOF
deb ${mirror} ${suite} ${comps}
deb ${mirror} ${suite}-updates ${comps}
deb http://security.debian.org/debian-security ${suite}-security ${comps}
EOF
}

mount_chroot_fs() {
  run mkdir -p /mnt/dev /mnt/proc /mnt/sys /mnt/run

  run mount --bind /dev  /mnt/dev
  run mount --bind /proc /mnt/proc
  run mount --bind /sys  /mnt/sys
  run mount --bind /run  /mnt/run
}

blk_uuid() {
  local dev="$1"
  local u=""
  u="$(blkid -s UUID -o value "$dev" 2>/dev/null || true)"
  [[ -n "$u" ]] || die "Cannot read UUID for $dev"
  echo "$u"
}

install_debian() {
  local suite="$1" mirror="$2"

  log "Debootstrap Debian ${suite} from ${mirror}"
  run debootstrap "$suite" /mnt "$mirror"

  # Ensure DNS works in chroot before any apt/systemctl operations
  run cp -f /etc/resolv.conf /mnt/etc/resolv.conf || true

  write_sources_list "/mnt" "$suite" "$mirror"
  mount_chroot_fs

  mkdir -p /mnt/etc
  [[ -f /mnt/etc/hosts ]] || cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
EOF
}

install_write_basic_config() {
  local hostname="$1" iface="$2" backend="$3" mode="$4" profile="$5" data="$6"
  local boot_mode="$7" p1="$8" p2="$9" p3="${10}"

  log "Writing hostname/hosts"
  echo "$hostname" > /mnt/etc/hostname
  if ! grep -qE "\s${hostname}(\s|$)" /mnt/etc/hosts 2>/dev/null; then
    echo "127.0.1.1   ${hostname}" >> /mnt/etc/hosts
  fi

  log "Writing fstab (UUID-based)"
  local boot_uuid swap_uuid esp_uuid

  boot_uuid="$(blk_uuid "$p2")"
  swap_uuid="$(blk_uuid "$p3")"

  if [[ "$boot_mode" == "uefi" ]]; then
    esp_uuid="$(blk_uuid "$p1")"
  cat > /mnt/etc/fstab <<EOF
/dev/pve/root        /          ext4  defaults     0 1
UUID=${boot_uuid}    /boot      ext4  defaults     0 2
UUID=${esp_uuid}     /boot/efi  vfat  umask=0077   0 1
UUID=${swap_uuid}    none       swap  sw           0 0
EOF
  else
  cat > /mnt/etc/fstab <<EOF
/dev/pve/root        /      ext4  defaults  0 1
UUID=${boot_uuid}    /boot  ext4  defaults  0 2
UUID=${swap_uuid}    none   swap  sw        0 0
EOF
  fi


  log "Configuring network backend=${backend}, mode=${mode}, profile=${profile:-n/a}"
  if [[ "$backend" == "networkd" ]]; then
    net_write_networkd "$iface" "$mode" "$profile" "$data"
  else
    net_write_ifupdown "$iface" "$mode" "$profile" "$data"
  fi
}

install_set_root_password() {
  local pass="$1"
  log "Setting root password (input not logged)"
  printf "root:%s\n" "$pass" | run_secret chroot /mnt chpasswd
}

install_base_packages() {
  local backend="$1"

  log "Installing base packages in chroot"
  run chroot /mnt bash -c "apt-get update -y"
  run chroot /mnt bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y     linux-image-amd64 initramfs-tools openssh-server sudo ca-certificates curl wget gnupg     lvm2 dmsetup kpartx locales tzdata"

  run chroot /mnt bash -c "systemctl enable ssh || systemctl enable sshd || true"

  if [[ "$backend" == "networkd" ]]; then
    log "Enabling systemd-networkd + systemd-resolved in target"
    run chroot /mnt bash -c "systemctl enable systemd-networkd systemd-resolved || true"
    run chroot /mnt bash -c "systemctl disable networking 2>/dev/null || true"
    run chroot /mnt bash -c "ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || true"
  else
    log "Ensuring ifupdown present and enabled in target"
    run chroot /mnt bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y ifupdown || true"
    run chroot /mnt bash -c "systemctl enable networking 2>/dev/null || true"
  fi
}
