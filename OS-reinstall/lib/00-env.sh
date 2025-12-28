#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="/root/ovh_pve_reinstall.log"
DUMP_DIR="/root/ovh_pve_reinstall_dump"
DUMP_TGZ="/root/ovh_pve_reinstall_dump.tgz"

STAGE="init"

BOOT_MODE=""
DISK=""
SWAP_GB=""
BOOT_SEL=""
BOOT_MIB=""
ROOT_GB=""
LVM_MODE=""
DEBREL=""
MIRROR=""
HOSTNAME=""
IFACE=""
NET_BACKEND=""
NET_MODE=""
STATIC_PROFILE=""
STATIC_DATA=""
ROOT_PASS=""

P1=""; P2=""; P3=""; P4=""
