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
source "$LIB_DIR/20-ui.sh"

validate_partition_sizes() {
  local disk_bytes boot_bytes swap_bytes root_bytes required_bytes

  disk_bytes="$(disk_get_size_bytes "$DISK" || true)"
  if [[ -z "$disk_bytes" ]]; then
    log "[!] disk size check skipped: lsblk unavailable or size unknown"
    return 0
  fi

  boot_bytes=$(( BOOT_SIZE_MIB * 1024 * 1024 ))
  swap_bytes=$(( SWAP_SIZE_GIB * 1024 * 1024 * 1024 ))
  if (( ROOT_SIZE_GIB == 0 )); then
    required_bytes=$(( boot_bytes + swap_bytes ))
  else
    root_bytes=$(( ROOT_SIZE_GIB * 1024 * 1024 * 1024 ))
    required_bytes=$(( boot_bytes + swap_bytes + root_bytes ))
  fi

  if (( required_bytes > disk_bytes )); then
    ui_msg "Выбранные размеры разделов превышают размер диска.\n\nДиск: ${DISK}\nРазмер диска: $(( disk_bytes / 1024 / 1024 / 1024 )) GiB\nТребуется: $(( required_bytes / 1024 / 1024 / 1024 )) GiB\n\nПожалуйста, уменьшите размеры разделов."
    return 1
  fi

  return 0
}

main() {
  log_init
  trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR
  require_root
  ui_init

  local rc 
  STAGE "welcome"

  while :; do
    case "$STAGE" in
      # ui_welcome
      welcome)
        ui_welcome || exit 0
        if detect_boot_mode_strict; then
          HAS_UEFI=1
        else
          HAS_UEFI=0
        fi
        STAGE "boot"
        ;;
      # ui_boot
      boot)
        if ui_pick_boot_mode BOOT_MODE BOOT_LABEL "$HAS_UEFI"; then
          rc=0
        else
          rc=$?
        fi
        case "$rc" in
          0) STAGE "disk" ;;
          2) STAGE "welcome" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_disk
      disk)
        if ui_pick_disk DISK; then
          rc=0
        else
          rc=$?
        fi
        case "$rc" in
          0) STAGE "lvm" ;;
          2) STAGE "boot" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_lvm
      lvm)
        rc=0
        ui_pick_lvm_mode LVM_MODE VG_NAME THINPOOL_NAME || rc=$?
        case "$rc" in
          0) STAGE "part_boot" ;;
          2) STAGE "boot" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_part_boot
      part_boot)
        if ui_pick_boot_size BOOT_SIZE_MIB; then
          rc=0
        else
          rc=$?
        fi
        case "$rc" in
          0) STAGE "part_swap" ;;
          2) STAGE "lvm" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_part_swap
      part_swap)
        if ui_pick_swap_size SWAP_SIZE_GIB; then
          rc=0
        else
          rc=$?
        fi
        case "$rc" in
          0) STAGE "part_root" ;;
          2) STAGE "part_boot" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_part_root
      part_root)
        if ui_pick_root_size ROOT_SIZE_GIB; then
          rc=0
        else
          rc=$?
        fi
        case "$rc" in
          0)
            if validate_partition_sizes; then
              state="debian"
            else
              state="part_root"
              continue
            fi
            ;;
          2) STAGE "part_swap" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_debian
      debian)
        rc=0
        ui_pick_debian_version DEBIAN_VERSION DEBIAN_SUITE || rc=$?
        case "$rc" in
          0) STAGE "mirror" ;;
          2) STAGE "part_root" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_mirror
      mirror)
        rc=0
        ui_pick_mirror DEBIAN_MIRROR || rc=$?
        case "$rc" in
          0) STAGE "hostname" ;;
          2) STAGE "debian" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_net_stack
      net_stack)
        rc=0
        ui_pick_net_stack NET_STACK "$DEBIAN_VERSION" "$DEBIAN_SUITE" || rc=$?
        case "$rc" in
          0) STAGE "net_iface" ;;
          2) STAGE "debian" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_net_iface
      net_iface)
        rc=0
        ui_pick_net_iface NET_IFACE || rc=$?
        case "$rc" in
          0) STAGE "net_mode" ;;
          2) STAGE "net_stack" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_net_mode
      net_mode)
        rc=0
        ui_pick_net_mode NET_MODE || rc=$?
        case "$rc" in
          0)
            if [[ "$NET_MODE" == "static" ]]; then
              STAGE "net_static"
            else
              STAGE "hostname"
            fi
            ;;
          2) STAGE "net_iface" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_net_static
      net_static)
        rc=0
        ui_pick_net_static NET_ADDR NET_GW NET_DNS || rc=$?
        case "$rc" in
          0) STAGE "hostname" ;;
          2) STAGE "net_mode" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_hostname
      hostname)
        rc=0
        ui_pick_hostname HOSTNAME_SHORT || rc=$?
        case "$rc" in
          0) STAGE "hosts" ;;
          2) STAGE "mirror" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_hosts
      hosts)
        rc=0
        ui_pick_hosts HOSTS_DOMAIN HOSTS_FQDN "$HOSTNAME_SHORT" || rc=$?
        case "$rc" in
          0) STAGE "root_pass" ;;
          2) STAGE "hostname" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_root_pass
      root_pass)
        rc=0
        ui_pick_root_password ROOT_PASS || rc=$?
        case "$rc" in
          0) STAGE "summary" ;;
          2)
            # назад: если static -> net_static, иначе -> net_mode
            if [[ "$NET_MODE" == "static" ]]; then
              STAGE "net_static"
            else
              STAGE "net_mode"
            fi
            ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_summary
      summary)
        rc=0
        ui_confirm_summary || rc=$?
        case "$rc" in
          0) break ;;          # пользователь подтвердил -> выходим из while и идём к execution
          2) STAGE "root_pass" ;;  # Назад -> на предыдущий шаг (поставь тот STAGE, который у тебя перед summary)
          *) exit 0 ;;
        esac
        ;;


      *) exit 1 ;;
    esac
  done
}


main "$@"
