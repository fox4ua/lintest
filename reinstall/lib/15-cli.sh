#!/usr/bin/env bash
# shellcheck shell=bash

# CLI parsing & usage.
# Requires: die() (from lib/00-log.sh)

usage() {
  cat <<'USAGE_EOF'
Usage:
  sudo ./install.sh --disk /dev/sdX [options]

Options:
  --disk /dev/sdX                (required)
  --release bullseye|bookworm|trixie|testing|sid
  --mirror http://deb.debian.org/debian
  --hostname myhost
  --boot-mode auto|uefi|bios

  --lvm-mode none|lvm|thin
  --vg-name vg0
  --root-size 30G
  --boot-size 256M|512M|1G|2G
  --swap none|1G|2G|4G
  --fs ext4|xfs|btrfs
  --data-fs ext4|xfs|btrfs
  --thinpool-pct-free 90         (thinpool = %FREE, default 90)

  --iface ens3
  --net dhcp|static
  --ip 203.0.113.10/24
  --gw 203.0.113.1
  --dns "1.1.1.1 8.8.8.8"
  --networkd 0|1

  --root-pass 'StrongPass'       (optional; if omitted, will prompt; empty locks root)
  --ssh-key-file /path/to/key
  --timezone Europe/Kyiv
  --yes
  -h, --help
USAGE_EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --disk) [[ $# -ge 2 ]] || die "Missing value for --disk"; DISK="$2"; shift 2;;
      --release) [[ $# -ge 2 ]] || die "Missing value for --release"; RELEASE="$2"; shift 2;;
      --mirror) [[ $# -ge 2 ]] || die "Missing value for --mirror"; MIRROR="$2"; shift 2;;
      --hostname) [[ $# -ge 2 ]] || die "Missing value for --hostname"; HOSTNAME="$2"; shift 2;;
      --boot-mode) [[ $# -ge 2 ]] || die "Missing value for --boot-mode"; BOOT_MODE="$2"; shift 2;;

      --lvm-mode) [[ $# -ge 2 ]] || die "Missing value for --lvm-mode"; LVM_MODE="$2"; shift 2;;
      --vg-name) [[ $# -ge 2 ]] || die "Missing value for --vg-name"; VG_NAME="$2"; shift 2;;
      --root-size) [[ $# -ge 2 ]] || die "Missing value for --root-size"; ROOT_SIZE="$2"; shift 2;;
      --boot-size) [[ $# -ge 2 ]] || die "Missing value for --boot-size"; BOOT_SIZE="$2"; shift 2;;
      --swap) [[ $# -ge 2 ]] || die "Missing value for --swap"; SWAP_CHOICE="$2"; shift 2;;
      --fs) [[ $# -ge 2 ]] || die "Missing value for --fs"; ROOT_FS="$2"; shift 2;;
      --data-fs) [[ $# -ge 2 ]] || die "Missing value for --data-fs"; DATA_FS="$2"; shift 2;;
      --thinpool-pct-free) [[ $# -ge 2 ]] || die "Missing value for --thinpool-pct-free"; THINPOOL_PCT_FREE="$2"; shift 2;;

      --iface) [[ $# -ge 2 ]] || die "Missing value for --iface"; IFACE="$2"; shift 2;;
      --net) [[ $# -ge 2 ]] || die "Missing value for --net"; NET_MODE="$2"; shift 2;;
      --ip) [[ $# -ge 2 ]] || die "Missing value for --ip"; IP_ADDR="$2"; shift 2;;
      --gw) [[ $# -ge 2 ]] || die "Missing value for --gw"; GW_ADDR="$2"; shift 2;;
      --dns) [[ $# -ge 2 ]] || die "Missing value for --dns"; DNS_ADDR="$2"; shift 2;;
      --networkd) [[ $# -ge 2 ]] || die "Missing value for --networkd"; USE_NETWORKD="$2"; shift 2;;

      --root-pass) [[ $# -ge 2 ]] || die "Missing value for --root-pass"; ROOT_PASS="$2"; shift 2;;
      --ssh-key-file) [[ $# -ge 2 ]] || die "Missing value for --ssh-key-file"; SSH_KEY_FILE="$2"; shift 2;;
      --timezone) [[ $# -ge 2 ]] || die "Missing value for --timezone"; TIMEZONE="$2"; shift 2;;
      --yes) ASSUME_YES="1"; shift 1;;

      -h|--help) usage; exit 0;;
      *) die "Unknown arg: $1";;
    esac
  done
}
