#!/usr/bin/env bash
# shellcheck shell=bash

# lib/exec/09-apt_install.sh
#
# Requires:
#   TARGET_DIR, LOG_FILE
#   DEBIAN_SUITE, DEBIAN_MIRROR
#   BOOT_MODE (uefi|biosgpt|biosmbr)
#   DISK
#   LVM_MODE (none|linear|thin)
#   HOSTNAME_SHORT (optional, default: debian)
#   HOSTS_DOMAIN (optional)
#   HOSTS_FQDN (optional)
#
# Depends on previous steps:
#   exec_in_chroot() (from 07-chroot_mounts.sh)
#   chroot mounts + resolv.conf already applied

: "${APT_COMPONENTS:=main}"
: "${APT_NONINTERACTIVE:=1}"

# packages installed inside target
: "${APT_BASE_PACKAGES:=ca-certificates,locales,dialog,udev,netbase,ifupdown,iproute2,isc-dhcp-client,openssh-server,curl,wget,gnupg}"
: "${APT_EXTRA_PACKAGES:=sudo,less,vim-tiny,chrony}"
: "${APT_LVM_PACKAGES:=lvm2,thin-provisioning-tools}"
: "${APT_GRUB_PACKAGES_UEFI:=grub-efi-amd64,efibootmgr}"
: "${APT_GRUB_PACKAGES_BIOS:=grub-pc}"

exec_apt_install_all() {
  : "${TARGET_DIR:?}"
  : "${LOG_FILE:?}"
  : "${DEBIAN_SUITE:?}"
  : "${DEBIAN_MIRROR:?}"
  : "${BOOT_MODE:?}"
  : "${DISK:?}"
  : "${LVM_MODE:?}"

  exec_progress 0 "Writing APT sources..."
  exec_apt_write_sources_list || return 1

  exec_progress 10 "Configuring APT (noninteractive)..."
  exec_apt_set_noninteractive || return 1

  exec_progress 20 "apt-get update..."
  exec_in_chroot apt-get update || return 1

  exec_progress 35 "Installing base packages..."
  exec_in_chroot apt-get install -y --no-install-recommends "$(exec_csv_to_space "$APT_BASE_PACKAGES")" || return 1

  exec_progress 45 "Installing extra packages..."
  exec_in_chroot apt-get install -y --no-install-recommends "$(exec_csv_to_space "$APT_EXTRA_PACKAGES")" || return 1

  if [[ "${LVM_MODE}" != "none" ]]; then
    exec_progress 55 "Installing LVM packages..."
    exec_in_chroot apt-get install -y --no-install-recommends "$(exec_csv_to_space "$APT_LVM_PACKAGES")" || return 1
  fi

  exec_progress 65 "Installing kernel..."
  exec_apt_install_kernel || return 1

  exec_progress 75 "Installing GRUB..."
  exec_apt_install_grub || return 1

  exec_progress 88 "Writing hostname/hosts..."
  exec_apt_write_hostname_hosts || return 1

  exec_progress 95 "Updating initramfs..."
  exec_in_chroot update-initramfs -u || return 1

  exec_progress 100 "APT + kernel + GRUB done."
  return 0
}

# ---------- helpers ----------

exec_csv_to_space() {
  # "a,b,c" -> "a b c"
  echo "$1" | tr ',' ' ' | awk '{$1=$1;print}'
}

exec_apt_write_sources_list() {
  local f="${TARGET_DIR}/etc/apt/sources.list"
  mkdir -p "${TARGET_DIR}/etc/apt" || true

  # Minimal classic sources.list (no security/updates splitting here; can extend later)
  cat >"$f" <<EOF
deb ${DEBIAN_MIRROR} ${DEBIAN_SUITE} ${APT_COMPONENTS}
deb ${DEBIAN_MIRROR} ${DEBIAN_SUITE}-updates ${APT_COMPONENTS}
deb http://security.debian.org/debian-security ${DEBIAN_SUITE}-security ${APT_COMPONENTS}
EOF

  return 0
}

exec_apt_set_noninteractive() {
  if (( APT_NONINTERACTIVE == 1 )); then
    mkdir -p "${TARGET_DIR}/etc/apt/apt.conf.d" || true
    cat >"${TARGET_DIR}/etc/apt/apt.conf.d/99noninteractive" <<EOF
Dpkg::Use-Pty "0";
APT::Get::Assume-Yes "true";
APT::Get::Fix-Missing "true";
EOF
  fi

  # Ensure /etc/environment has DEBIAN_FRONTEND for some postinst scripts
  cat >"${TARGET_DIR}/etc/environment" <<EOF
DEBIAN_FRONTEND=noninteractive
EOF

  return 0
}

exec_apt_install_kernel() {
  # Prefer metapackage linux-image-amd64 on amd64, otherwise generic linux-image
  # This is adequate for Debian 11/12/13.
  exec_in_chroot sh -c 'apt-get install -y --no-install-recommends linux-image-amd64 || apt-get install -y --no-install-recommends linux-image' || return 1
  return 0
}

exec_apt_install_grub() {
  case "${BOOT_MODE}" in
    uefi)
      exec_in_chroot apt-get install -y --no-install-recommends "$(exec_csv_to_space "$APT_GRUB_PACKAGES_UEFI")" || return 1

      # Ensure EFI dir exists (it is mounted already by step 6 if UEFI)
      exec_in_chroot mkdir -p /boot/efi || true

      # Install GRUB to EFI (use --removable for safety in some VPS/OVH cases)
      exec_in_chroot grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck --no-nvram || return 1
      exec_in_chroot update-grub || return 1
      ;;
    biosgpt|biosmbr)
      exec_in_chroot apt-get install -y --no-install-recommends "$(exec_csv_to_space "$APT_GRUB_PACKAGES_BIOS")" || return 1
      # Install to disk (MBR for biosmbr, protective MBR for biosgpt)
      exec_in_chroot grub-install --target=i386-pc --recheck "${DISK}" || return 1
      exec_in_chroot update-grub || return 1
      ;;
    *)
      ui_msg "Unknown BOOT_MODE=${BOOT_MODE}\nLog: ${LOG_FILE}"
      return 1
      ;;
  esac

  return 0
}

exec_apt_write_hostname_hosts() {
  local hn="${HOSTNAME_SHORT:-debian}"
  local domain="${HOSTS_DOMAIN:-localdomain}"
  local fqdn="${HOSTS_FQDN:-}"

  echo "$hn" >"${TARGET_DIR}/etc/hostname"

  # Minimal /etc/hosts
  cat >"${TARGET_DIR}/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 ${hn}.${domain} ${hn}
::1       localhost ip6-localhost ip6-loopback
ff02::1   ip6-allnodes
ff02::2   ip6-allrouters
EOF

  # If user provided explicit FQDN, ensure it is present
  if [[ -n "$fqdn" ]]; then
    echo "127.0.1.1 ${fqdn} ${hn}" >>"${TARGET_DIR}/etc/hosts"
  fi

  return 0
}
