#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# Config (override via env or CLI args)
###############################################################################
DISK="${DISK:-}"
RELEASE="${RELEASE:-bookworm}"              # bullseye|bookworm|trixie|testing|sid
MIRROR="${MIRROR:-http://deb.debian.org/debian}"
HOSTNAME="${HOSTNAME:-debian}"
ARCH="${ARCH:-amd64}"

BOOT_MODE="${BOOT_MODE:-auto}"              # auto|uefi|bios
EFI_SIZE="${EFI_SIZE:-512M}"                # fixed for UEFI
BOOT_SIZE="${BOOT_SIZE:-}"                  # 256M|512M|1G|2G (if empty -> prompt)
SWAP_CHOICE="${SWAP_CHOICE:-}"              # none|1G|2G|4G (if empty -> prompt)
ROOT_SIZE="${ROOT_SIZE:-}"                  # e.g. 30G (if empty -> prompt)

ROOT_FS="${ROOT_FS:-ext4}"                  # ext4|xfs|btrfs
DATA_FS="${DATA_FS:-$ROOT_FS}"              # default same as root

# Storage mode: none|lvm|thin (if empty -> prompt)
LVM_MODE="${LVM_MODE:-}"
VG_NAME="${VG_NAME:-vg0}"
LV_ROOT_NAME="${LV_ROOT_NAME:-root}"
LV_SWAP_NAME="${LV_SWAP_NAME:-swap}"
LV_DATA_NAME="${LV_DATA_NAME:-data}"
THINPOOL_NAME="${THINPOOL_NAME:-thinpool}"
THINPOOL_PERCENT="${THINPOOL_PERCENT:-90}"  # thinpool = 90%FREE (headroom)

NET_MODE="${NET_MODE:-dhcp}"                # dhcp|static
IFACE="${IFACE:-}"                          # e.g. ens3
IP_ADDR="${IP_ADDR:-}"                      # e.g. 203.0.113.10/24
GW_ADDR="${GW_ADDR:-}"                      # e.g. 203.0.113.1
DNS_ADDR="${DNS_ADDR:-1.1.1.1 8.8.8.8}"
USE_NETWORKD="${USE_NETWORKD:-0}"           # 1 = systemd-networkd, 0 = ifupdown

ROOT_PASS="${ROOT_PASS:-}"                  # if empty -> prompt; empty input locks root
SSH_KEY_FILE="${SSH_KEY_FILE:-}"            # path to public key or authorized_keys for root
TIMEZONE="${TIMEZONE:-UTC}"

TARGET="${TARGET:-/mnt/target}"
LOG_FILE="${LOG_FILE:-/root/debootstrap_install.log}"

ASSUME_YES="${ASSUME_YES:-0}"               # 1 = no destructive confirmation prompt
USE_DIALOG="${USE_DIALOG:-1}"               # 1 = dialog UI if available, 0 = CLI prompts
