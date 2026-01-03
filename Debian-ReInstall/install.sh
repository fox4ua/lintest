#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export BASE_DIR

# переменные
source "$BASE_DIR/lib/00-env.sh"
# логирование
source "$LIB_DIR/10-log.sh"
# дополнительные функции
source "$INIT_DIR/01-require_root.sh"
source "$INIT_DIR/02-boot_detect.sh"
source "$INIT_DIR/03-disk_detect.sh"
# остальное

source "$LIB_DIR/ui.sh"


main() {
  log_init
  trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR
  # check root
  require_root
  ui_init

  local rc=0

  while true; do
    # 1) welcome
    ui_welcome || exit 0

    # 2) detect uefi BEFORE boot menu
    while true; do
      rc=0
      ui_pick_boot_mode BOOT_MODE BOOT_LABEL "$HAS_UEFI" || rc=$?
      case "$rc" in
        0) : ;;          # OK -> идём к диску
        2) break ;;      # Back -> welcome
        *) exit 0 ;;     # Cancel/ESC
      esac

      # Step 3: Disk loop (Back -> boot)
      while true; do
        rc=0
        ui_pick_disk DISK || rc=$?
        case "$rc" in
          0) : ;;
          2) break ;;    # Back -> boot menu
          *) exit 0 ;;   # Cancel/ESC
        esac

        # Step 4: Partitions wizard with strict Back:
        # root -> swap -> boot -> disk
        local part_stage="boot"

        while true; do
          case "$part_stage" in
            boot)
              rc=0
              ui_pick_boot_size BOOT_SIZE_MIB || rc=$?
              case "$rc" in
                0) part_stage="swap" ;;  # далее -> swap
                2) part_stage="disk" ;;  # назад -> диск
                *) exit 0 ;;
              esac
              ;;

            swap)
              rc=0
              ui_pick_swap_size SWAP_SIZE_GIB || rc=$?
              case "$rc" in
                0) part_stage="root" ;;  # далее -> root
                2) part_stage="boot" ;;  # назад -> boot
                *) exit 0 ;;
              esac
              ;;

            root)
              rc=0
              ui_pick_root_size ROOT_SIZE_GIB || rc=$?
              case "$rc" in
                0) part_stage="done" ;;  # готово
                2) part_stage="swap" ;;  # назад -> swap
                *) exit 0 ;;
              esac
              ;;

            disk)
              # вернуться к выбору диска
              break
              ;;

            done)
              # всё выбрано -> выходим из disk+boot+welcome циклов (как у тебя)
              break 3
              ;;

            *)
              # fallback
              break
              ;;
          esac
        done

        # если вышли из wizard на "disk" -> заново показать ui_pick_disk
        # (мы тут продолжаем внешний disk-loop)
      done
      # если вышли из disk-loop по Back -> показываем boot menu снова
    done
  done


  ui_msg "План установки:\n\n${BOOT_LABEL}\nДиск: ${DISK}\n\n/boot: ${BOOT_SIZE_MIB} MiB\nswap: ${SWAP_SIZE_GIB} GiB\nroot: ${ROOT_SIZE_GIB} GiB (0=остаток)\n\nDISK_RELEASE_APPROVED=${DISK_RELEASE_APPROVED:-0}"
}

main "$@"
