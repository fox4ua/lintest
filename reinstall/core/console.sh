#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export BASE_DIR


# ===== config storage =====
# Можно заменить на ассоц.массив CFG[], но оставляем переменные для совместимости с вашим проектом.
DISK="${DISK:-}"             # /dev/sda
BOOT_MODE="${BOOT_MODE:-}"   # uefi|bios (legacy)
LVM_MODE="${LVM_MODE:-}"     # none|lvm|thin
VG_NAME="${VG_NAME:-}"
THINPOOL_NAME="${THINPOOL_NAME:-}"
THINPOOL_PERCENT="${THINPOOL_PERCENT:-}"

DEBIAN_MAJOR="${DEBIAN_MAJOR:-}"
DEBIAN_CODENAME="${DEBIAN_CODENAME:-}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-}"
BOOT_SIZE="${BOOT_SIZE:-}"   # 256M|512M|1G
SWAP_CHOICE="${SWAP_CHOICE:-}" # none|1G|2G|4G




UI_MODE="${UI_MODE:-}"       # none|console|dialog (пока делаем console)

ROOT_SIZE="${ROOT_SIZE:-}"   # 30G etc
ROOT_PASS="${ROOT_PASS:-}"
ROOT_PASS_SET="${ROOT_PASS_SET:-0}" # 0=не задано, 1=задано (в т.ч. пустое)

DIALOGS_DIR="$BASE_DIR/console"

# ===== helpers =====
die(){ echo "ERROR: $*" >&2; exit 1; }

# ===== load dialogs =====
# shellcheck source=/dev/null
source "$DIALOGS_DIR/10-disk.sh"
source "$DIALOGS_DIR/15-boot-mode.sh"
source "$DIALOGS_DIR/40-lvm-mode.sh"
source "$DIALOGS_DIR/45-vg-name.sh"
source "$DIALOGS_DIR/46-thinpool-name.sh"
source "$DIALOGS_DIR/47-thinpool-percent.sh"


source "$DIALOGS_DIR/20-release.sh"
source "$DIALOGS_DIR/25-mirror.sh"
source "$DIALOGS_DIR/50-boot-size.sh"
source "$DIALOGS_DIR/60-swap.sh"


source "$DIALOGS_DIR/70-root-size.sh"
source "$DIALOGS_DIR/80-root-pass.sh"
source "$DIALOGS_DIR/90-summary.sh"

validate_config() {
  [[ -n "$DEBIAN_MIRROR" ]] || die "DEBIAN_MIRROR is empty"
  [[ "$DEBIAN_MIRROR" =~ ^https?://[^[:space:]]+$ ]] || die "Invalid DEBIAN_MIRROR=$DEBIAN_MIRROR"
  if [[ "$LVM_MODE" == "lvm" || "$LVM_MODE" == "thin" ]]; then
    [[ -n "$VG_NAME" ]] || die "VG_NAME is empty (required for LVM/thin)"
    [[ "$VG_NAME" =~ ^[A-Za-z0-9_][A-Za-z0-9._+-]*$ ]] || die "Invalid VG_NAME=$VG_NAME"
  else
    # при no-lvm VG_NAME должен быть пустым
    VG_NAME=""
  fi


  [[ -n "$UI_MODE" ]] || die "UI_MODE is empty"
  [[ -n "$BOOT_MODE" ]] || die "BOOT_MODE is empty"
  [[ -n "$DISK" ]] || die "DISK is empty"
  case "$BOOT_MODE" in auto|uefi|bios) :;; *) die "Invalid BOOT_MODE=$BOOT_MODE";; esac
  case "$LVM_MODE" in none|lvm|thin) :;; *) die "Invalid LVM_MODE=$LVM_MODE";; esac
  case "$BOOT_SIZE" in 256M|512M|1G) :;; *) die "Invalid BOOT_SIZE=$BOOT_SIZE";; esac
  case "$SWAP_CHOICE" in none|1G|2G|4G) :;; *) die "Invalid SWAP_CHOICE=$SWAP_CHOICE";; esac
  [[ "$ROOT_SIZE" =~ ^[0-9]+[GM]$ ]] || die "Invalid ROOT_SIZE=$ROOT_SIZE (пример: 30G)"
  # ROOT_PASS может быть пустым (LOCK root) — это ок, но важно различать "не задано"
  [[ "$ROOT_PASS_SET" == "1" ]] || die "ROOT_PASS not set (should be set, even if empty)"
}

main() {
  # choose disk
  ui_pick_disk_console DISK
  # choose boot mode
  ui_pick_boot_mode_console BOOT_MODE
  
  ui_pick_lvm_mode_console LVM_MODE || exit 0

  if [[ "$LVM_MODE" == "lvm" || "$LVM_MODE" == "thin" ]]; then
    ui_pick_vg_name_console VG_NAME || exit 0
  else
    VG_NAME=""   # чтобы не тянуть мусор, когда LVM не используется
  fi
  
  if [[ "$LVM_MODE" == "thin" ]]; then
    ui_pick_thinpool_name_console THINPOOL_NAME || exit 0
    ui_pick_thinpool_percent_console THINPOOL_PERCENT || exit 0
  else
    THINPOOL_NAME=""
    THINPOOL_PERCENT=""
  fi
  
  
  
  # choose debian release
  ui_pick_debian_release_console DEBIAN_MAJOR DEBIAN_CODENAME
  # choose debian mirror
  ui_pick_debian_mirror_console DEBIAN_MIRROR || exit 0

  
  
  
  
  ui_pick_boot_size_console BOOT_SIZE
  
  ui_pick_swap_console SWAP_CHOICE

  ui_pick_root_size_console ROOT_SIZE



  # 2) Дальше — отдельные диалоги, каждый заполняет одну группу параметров


  # Пароль: пустой = LOCK root; но обязательно выставляем ROOT_PASS_SET=1
  ui_prompt_root_pass_console ROOT_PASS ROOT_PASS_SET

  # 3) Проверка
  validate_config

  # 4) Сводка
  ui_print_summary
}

main "$@"
