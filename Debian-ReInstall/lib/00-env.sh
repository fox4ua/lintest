#!/usr/bin/env bash
# Проверка наличия BASE_DIR
: "${BASE_DIR:?BASE_DIR is not set (source install.sh first)}"
# Пути (чтобы все остальные файлы не вычисляли их заново)
LIB_DIR="${LIB_DIR:-$BASE_DIR/lib}"
INIT_DIR="${INIT_DIR:-$LIB_DIR/init}"
UI_DIR="${UI_DIR:-$LIB_DIR/ui}"
# Файл логов
LOG_FILE="${LOG_FILE:-/root/debian_installer.log}"
# boot mode
HAS_UEFI="${HAS_UEFI:-0}"
BOOT_MODE="${BOOT_MODE:-}"
BOOT_LABEL="${BOOT_LABEL:-}"


DISK="${DISK:-}"

DISK_NEEDS_RELEASE="${DISK_NEEDS_RELEASE:-0}"     # диск занят чем-то
DISK_RELEASE_APPROVED="${DISK_RELEASE_APPROVED:-0}" # пользователь согласен “Отключить” позже

DISK_HAS_MOUNTS="${DISK_HAS_MOUNTS:-0}"
DISK_HAS_SWAP="${DISK_HAS_SWAP:-0}"
DISK_HAS_LVM="${DISK_HAS_LVM:-0}"
DISK_HAS_MD="${DISK_HAS_MD:-0}"

# Файлы/папки
TARGET_DIR="${TARGET_DIR:-/mnt/target}"

# Глобальные значения мастера (заполняются по мере прохождения)
STAGE="${STAGE:-init}"



# (на будущее)
DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"
HOSTNAME="${HOSTNAME:-debian}"
