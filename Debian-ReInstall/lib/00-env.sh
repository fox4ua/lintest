#!/usr/bin/env bash
# Проверка наличия BASE_DIR
: "${BASE_DIR:?BASE_DIR is not set (source install.sh first)}"
# Пути (чтобы все остальные файлы не вычисляли их заново)
LIB_DIR="${LIB_DIR:-$BASE_DIR/lib}"
INIT_DIR="${INIT_DIR:-$LIB_DIR/init}"
UI_DIR="${UI_DIR:-$LIB_DIR/ui}"
# Файл логов
LOG_FILE="${LOG_FILE:-/root/debian_installer.log}"




# Файлы/папки
TARGET_DIR="${TARGET_DIR:-/mnt/target}"

# Глобальные значения мастера (заполняются по мере прохождения)
STAGE="${STAGE:-init}"

HAS_UEFI="${HAS_UEFI:-0}"
BOOT_MODE="${BOOT_MODE:-}"
BOOT_LABEL="${BOOT_LABEL:-}"

# (на будущее)
DISK="${DISK:-}"
DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"
HOSTNAME="${HOSTNAME:-debian}"
