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
DISK_NEEDS_RELEASE="${DISK_NEEDS_RELEASE:-0}"       # диск занят чем-то
DISK_RELEASE_APPROVED="${DISK_RELEASE_APPROVED:-0}" # пользователь согласен “Отключить” позже
DISK_HAS_MOUNTS="${DISK_HAS_MOUNTS:-0}"
DISK_HAS_SWAP="${DISK_HAS_SWAP:-0}"
DISK_HAS_LVM="${DISK_HAS_LVM:-0}"
DISK_HAS_MD="${DISK_HAS_MD:-0}"
# LVM
LVM_MODE="${LVM_MODE:-linear}"                      # linear|thin|none
VG_NAME="${VG_NAME:-pve}"                           # имя VG (если LVM включён)
THINPOOL_NAME="${THINPOOL_NAME:-data}"              # имя thinpool (если thin)
# Partitions
BOOT_SIZE_MIB="${BOOT_SIZE_MIB:-512}"               # /boot (MiB)
SWAP_SIZE_GIB="${SWAP_SIZE_GIB:-1}"                 # swap (GiB)
ROOT_SIZE_GIB="${ROOT_SIZE_GIB:-30}"                # root (GiB)
# debian
DEBIAN_VERSION="${DEBIAN_VERSION:-12}"              # 11|12|13
DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"            # bullseye|bookworm|trixie
# mirror
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
# hostname / host
HOSTNAME_SHORT="${HOSTNAME_SHORT:-debian}"
HOSTS_DOMAIN="${HOSTS_DOMAIN:-localdomain}"
HOSTS_FQDN="${HOSTS_FQDN:-}"

NET_STACK="${NET_STACK:-}"   # networkd|ifupdown|"" (если пусто — выберем через UI)

NET_MODE="${NET_MODE:-dhcp}"      # dhcp|static
NET_IFACE="${NET_IFACE:-}"        # выберем позже отдельным окном (пока пусто)

NET_ADDR="${NET_ADDR:-}"          # static: IP/CIDR, пример 192.168.1.10/24
NET_GW="${NET_GW:-}"              # static: gateway, пример 192.168.1.1
NET_DNS="${NET_DNS:-}"            # static: DNS через пробел, пример "1.1.1.1 8.8.8.8"





# Файлы/папки
TARGET_DIR="${TARGET_DIR:-/mnt/target}"

# Глобальные значения мастера (заполняются по мере прохождения)
STAGE="${STAGE:-init}"



# (на будущее)
DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"
HOSTNAME="${HOSTNAME:-debian}"
