#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export BASE_DIR


# ===== config storage =====
# Можно заменить на ассоц.массив CFG[], но оставляем переменные для совместимости с вашим проектом.
UI_MODE="${UI_MODE:-}"       # none|console|dialog (пока делаем console)
BOOT_MODE="${BOOT_MODE:-}"   # uefi|bios (legacy)
DISK="${DISK:-}"             # /dev/sda
LVM_MODE="${LVM_MODE:-}"     # none|lvm|thin
BOOT_SIZE="${BOOT_SIZE:-}"   # 256M|512M|1G
SWAP_CHOICE="${SWAP_CHOICE:-}" # none|1G|2G|4G
ROOT_SIZE="${ROOT_SIZE:-}"   # 30G etc
ROOT_PASS="${ROOT_PASS:-}"
ROOT_PASS_SET="${ROOT_PASS_SET:-0}" # 0=не задано, 1=задано (в т.ч. пустое)

DIALOGS_DIR="$BASE_DIR/dialogs"

# ===== helpers =====
die(){ echo "ERROR: $*" >&2; exit 1; }

# ===== load dialogs =====
# shellcheck source=/dev/null
source "$DIALOGS_DIR/10-ui-mode.sh"
source "$DIALOGS_DIR/20-boot-mode.sh"
source "$DIALOGS_DIR/30-disk.sh"
source "$DIALOGS_DIR/40-lvm-mode.sh"
source "$DIALOGS_DIR/50-boot-size.sh"
source "$DIALOGS_DIR/60-swap.sh"
source "$DIALOGS_DIR/70-root-size.sh"
source "$DIALOGS_DIR/80-root-pass.sh"
source "$DIALOGS_DIR/90-summary.sh"

validate_config() {
  [[ -n "$UI_MODE" ]] || die "UI_MODE is empty"
  [[ -n "$BOOT_MODE" ]] || die "BOOT_MODE is empty"
  [[ -n "$DISK" ]] || die "DISK is empty"
  case "$BOOT_MODE" in uefi|bios) :;; *) die "Invalid BOOT_MODE=$BOOT_MODE";; esac
  case "$LVM_MODE" in none|lvm|thin) :;; *) die "Invalid LVM_MODE=$LVM_MODE";; esac
  case "$BOOT_SIZE" in 256M|512M|1G) :;; *) die "Invalid BOOT_SIZE=$BOOT_SIZE";; esac
  case "$SWAP_CHOICE" in none|1G|2G|4G) :;; *) die "Invalid SWAP_CHOICE=$SWAP_CHOICE";; esac
  [[ "$ROOT_SIZE" =~ ^[0-9]+[GM]$ ]] || die "Invalid ROOT_SIZE=$ROOT_SIZE (пример: 30G)"
  # ROOT_PASS может быть пустым (LOCK root) — это ок, но важно различать "не задано"
  [[ "$ROOT_PASS_SET" == "1" ]] || die "ROOT_PASS not set (should be set, even if empty)"
}

main() {
  # 1) Выбор режима UI (пока поддерживаем console; оставляем поле под будущее)
  ui_pick_mode_console UI_MODE

  # 2) Дальше — отдельные диалоги, каждый заполняет одну группу параметров
  ui_pick_boot_mode_console BOOT_MODE
  ui_pick_disk_console DISK
  ui_pick_lvm_mode_console LVM_MODE
  ui_pick_boot_size_console BOOT_SIZE
  ui_pick_swap_console SWAP_CHOICE
  ui_pick_root_size_console ROOT_SIZE

  # Пароль: пустой = LOCK root; но обязательно выставляем ROOT_PASS_SET=1
  ui_prompt_root_pass_console ROOT_PASS ROOT_PASS_SET

  # 3) Проверка
  validate_config

  # 4) Сводка
  ui_print_summary
}

main "$@"
