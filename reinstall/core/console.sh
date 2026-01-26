#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export BASE_DIR

DIALOGS_DIR="$BASE_DIR/console"


# ===== config storage =====
# Можно заменить на ассоц.массив CFG[], но оставляем переменные для совместимости с вашим проектом.
DISK            ="${DISK:-}"              # /dev/sda
BOOT_MODE       ="${BOOT_MODE:-}"         # uefi|bios (legacy)
LVM_MODE        ="${LVM_MODE:-}"          # none|lvm|thin
VG_NAME         ="${VG_NAME:-}"           #
THINPOOL_NAME   ="${THINPOOL_NAME:-}"     #
THINPOOL_PERCENT="${THINPOOL_PERCENT:-}"  #
BOOT_SIZE       ="${BOOT_SIZE:-}"         # 256|512|1024 (MiB)
SWAP_SIZE       ="${SWAP_SIZE:-}"         # 0|1024|2048|4096 (MiB)
ROOT_FS         ="${ROOT_FS:-ext4}"       # ext4|xfs|btrfs
ROOT_SIZE       ="${ROOT_SIZE:-}"         # size in GiB (digits only)
DATA_FS         ="${DATA_FS:-ext4}"       # ext4|xfs|btrfs
DEBIAN_MAJOR    ="${DEBIAN_MAJOR:-}"
DEBIAN_CODENAME ="${DEBIAN_CODENAME:-}"
DEBIAN_MIRROR   ="${DEBIAN_MIRROR:-}"
HOSTNAME        ="${HOSTNAME:-}"
HOSTS_FQDN      ="${HOSTS_FQDN:-}"
TIMEZONE        ="${TIMEZONE:-}"
USE_NETWORKD    ="${USE_NETWORKD:-}"
IFACE           ="${IFACE:-}"
NET4_MODE       ="${NET4_MODE:-dhcp}"
IP4_CIDR        ="${IP4_CIDR:-}"
GW4             ="${GW4:-}"
DNS4            ="${DNS4:-}"
NET6_MODE       ="${NET6_MODE:-auto}"
IP6_CIDR        ="${IP6_CIDR:-}"
GW6             ="${GW6:-}"
DNS6            ="${DNS6:-}"
ROOT_PASS       ="${ROOT_PASS:-}"




# ===== helpers =====
die(){ echo "ERROR: $*" >&2; exit 1; }

# ===== load dialogs =====
source "$BASE_DIR/init/10-disk-checks.sh"
source "$BASE_DIR/init/20-size-checks.sh"
source "$BASE_DIR/init/25-iface-detect.sh"
source "$BASE_DIR/init/30-net4-detect.sh"
source "$BASE_DIR/init/35-net6-detect.sh"

source "$BASE_DIR/init/90-validate-console.sh"
# shellcheck source=/dev/null
source "$DIALOGS_DIR/10-disk.sh"
source "$DIALOGS_DIR/15-boot-mode.sh"
source "$DIALOGS_DIR/20-lvm-mode.sh"
source "$DIALOGS_DIR/21-vg-name.sh"
source "$DIALOGS_DIR/22-thinpool-name.sh"
source "$DIALOGS_DIR/23-thinpool-percent.sh"
source "$DIALOGS_DIR/30-boot-size.sh"
source "$DIALOGS_DIR/31-swap.sh"
source "$DIALOGS_DIR/32-root-fs.sh"
source "$DIALOGS_DIR/33-root-size.sh"
source "$DIALOGS_DIR/34-data-fs.sh"
source "$DIALOGS_DIR/40-release.sh"
source "$DIALOGS_DIR/45-mirror.sh"
source "$DIALOGS_DIR/50-hostname.sh"
source "$DIALOGS_DIR/51-hosts-fqdn.sh"
source "$DIALOGS_DIR/52-timezone.sh"

source "$DIALOGS_DIR/60-networkd.sh"
source "$DIALOGS_DIR/61-iface.sh"
source "$DIALOGS_DIR/62-net4-mode.sh"
source "$DIALOGS_DIR/63-ipv4-ip.sh"
source "$DIALOGS_DIR/64-ipv4-gw.sh"
source "$DIALOGS_DIR/65-ipv4-dns.sh"
source "$DIALOGS_DIR/66-net6-mode.sh"
source "$DIALOGS_DIR/67-ipv6-ip.sh"
source "$DIALOGS_DIR/68-ipv6-gw.sh"
source "$DIALOGS_DIR/69-ipv6-dns.sh"
source "$DIALOGS_DIR/70-root-pass.sh"

source "$DIALOGS_DIR/90-summary.sh"
# main console dialog
main() {
  # choose disk
  ui_pick_disk_console DISK || exit 0
  # choose boot mode
  ui_pick_boot_mode_console BOOT_MODE || exit 0
  # choose lvm mode
  ui_pick_lvm_mode_console LVM_MODE || exit 0
  # input lvm name
  if [[ "$LVM_MODE" == "lvm" || "$LVM_MODE" == "thin" ]]; then
    ui_pick_vg_name_console VG_NAME || exit 0
  else
    VG_NAME=""
  fi
  # input thinpool name / thinpool percent of FREE space (only for LVM thin)
  if [[ "$LVM_MODE" == "thin" ]]; then
    ui_pick_thinpool_name_console THINPOOL_NAME || exit 0
    ui_pick_thinpool_percent_console THINPOOL_PERCENT || exit 0
  else
    THINPOOL_NAME=""
    THINPOOL_PERCENT=""
  fi
  # choose boot size
  ui_pick_boot_size_console BOOT_SIZE || exit 0
  # choose swap size
  ui_pick_swap_console SWAP_SIZE || exit 0
  # choose
  ui_pick_root_fs_console ROOT_FS || exit 0
  # input
  ui_pick_root_size_console ROOT_SIZE || exit 0


  # choose
  # BOOT_MODE может быть auto -> используй effective как ранее
  boot_mode_effective="$BOOT_MODE"
  if [[ "$BOOT_MODE" == "auto" ]]; then
    if [[ -n "${BOOT_MODE_EFFECTIVE:-}" ]]; then
      boot_mode_effective="$BOOT_MODE_EFFECTIVE"
    elif [[ -n "${BOOT_MODE_AUTO_EFFECTIVE:-}" ]]; then
      boot_mode_effective="$BOOT_MODE_AUTO_EFFECTIVE"
    elif [[ -d /sys/firmware/efi ]]; then
      boot_mode_effective="uefi"
    else
      boot_mode_effective="bios"
    fi
  fi
  if [[ "$boot_mode_effective" != "uefi" && "$boot_mode_effective" != "bios" ]]; then
    die "Invalid effective BOOT_MODE=$boot_mode_effective"
  fi

  # если root “съел всё” (или почти всё) — пропускаем data-fs
  if has_space_for_data_fs "$DISK" "$ROOT_SIZE" "$boot_mode_effective" "$EFI_SIZE" "$BOOT_SIZE" "$SWAP_SIZE" 1; then
    ui_pick_data_fs_console DATA_FS || exit 0
  else
    DATA_FS=""   # не спрашиваем
  fi



  # choose debian release
  ui_pick_debian_release_console DEBIAN_MAJOR DEBIAN_CODENAME || exit 0
  # choose debian mirror
  ui_pick_debian_mirror_console DEBIAN_MIRROR || exit 0
  # input hostname
  ui_pick_hostname_console HOSTNAME || exit 0
  # input hosts
  ui_pick_hosts_fqdn_console HOSTS_FQDN || exit 0
  # input timezone
  ui_pick_timezone_console TIMEZONE || exit 0
  #
  ui_pick_networkd_console USE_NETWORKD || exit 0
  #
  ui_pick_iface_console IFACE || exit 0
  #
  ui_pick_net4_mode_console NET4_MODE || exit 0
  #
  if [[ "$NET4_MODE" == "static" ]]; then
    ui_pick_net4_ip_console  IP4_CIDR || exit 0
    ui_pick_net4_gw_console  GW4      || exit 0
    ui_pick_net4_dns_console DNS4     || exit 0
  else
    IP4_CIDR=""
    GW4=""
    DNS4=""
  fi

  # IPv6: запрет off, если IPv4=off
  NET6_FORBID_OFF=0
  [[ "$NET4_MODE" == "off" ]] && NET6_FORBID_OFF=1

  ui_pick_net6_mode_console NET6_MODE || exit 0

  if [[ "$NET6_MODE" == "static" ]]; then
    ui_pick_net6_ip_console  IP6_CIDR || exit 0
    ui_pick_net6_gw_console  GW6      || exit 0
    ui_pick_net6_dns_console DNS6     || exit 0
  else
    IP6_CIDR=""
    GW6=""
    DNS6=""
  fi

  unset NET6_FORBID_OFF

  ui_pick_root_pass_console ROOT_PASS || exit 0

  # 3) Проверка
  validate_config

  # 4) Сводка
  ui_print_summary
}

main "$@"
