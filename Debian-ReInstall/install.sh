#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export BASE_DIR
# переменные
source "$BASE_DIR/lib/00-env.sh"
# логирование
source "$LIB_DIR/10-log.sh"
# дополнительные функции
source "$INIT_DIR/00-ui_deps.sh"
source "$INIT_DIR/01-require_root.sh"
source "$INIT_DIR/02-boot_detect.sh"
source "$INIT_DIR/03-disk_detect.sh"
source "$INIT_DIR/04-validate_partition.sh"
source "$INIT_DIR/05-validate_required.sh"
source "$INIT_DIR/06-mirror_probe.sh"
source "$INIT_DIR/07-net_current.sh"
# остальное
source "$LIB_DIR/20-ui.sh"


main() {
  log_init
  trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR
  require_root
  ui_init
  local rc
  stage "welcome"

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
        stage "boot"
        ;;
      # ui_boot
      boot)
        if ui_pick_boot_mode BOOT_MODE BOOT_LABEL "$HAS_UEFI"; then
          rc=0
        else
          rc=$?
        fi
        case "$rc" in
          0) stage "disk" ;;
          2) stage "welcome" ;;
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
          0) stage "lvm" ;;
          2) stage "boot" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_lvm
      lvm)
        rc=0
        ui_pick_lvm_mode LVM_MODE VG_NAME THINPOOL_NAME || rc=$?
        case "$rc" in
          0) stage "part_boot" ;;
          2) stage "disk" ;;
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
          0) stage "part_swap" ;;
          2) stage "lvm" ;;
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
          0) stage "part_root" ;;
          2) stage "part_boot" ;;
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
              stage "debian"
            else
              stage "part_root"
              continue
            fi
            ;;
          2) stage "part_swap" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_debian
      debian)
        rc=0
        ui_pick_debian_version DEBIAN_VERSION DEBIAN_SUITE || rc=$?
        case "$rc" in
          0) stage "mirror" ;;
          2) stage "part_root" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_mirror
      mirror)
        rc=0
        ui_pick_mirror DEBIAN_MIRROR || rc=$?
        case "$rc" in
          0) stage "net_current" ;;
          2) stage "debian" ;;
          *) exit 0 ;;
        esac
        ;;

      # ui_net_current
      net_current)
        rc=0
        ui_show_net_current "$NET_STACK" || rc=$?
        case "$rc" in
          0) stage "net_stack" ;;
          2) stage "mirror" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_net_stack
      net_stack)
        rc=0
        ui_pick_net_stack NET_STACK "$DEBIAN_VERSION" "$DEBIAN_SUITE" || rc=$?
        case "$rc" in
          0) stage "net_iface" ;;
          2) stage "net_current" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_net_iface
      net_iface)
        rc=0
        ui_pick_net_iface NET_IFACE || rc=$?
        case "$rc" in
          0) stage "net4_enable" ;;
          2) stage "net_stack" ;;
          *) exit 0 ;;
        esac
        ;;
      net4_enable)
        rc=0
        ui_pick_net4_enable NET4_ENABLE || rc=$?
        case "$rc" in
          0)
            if [[ "$NET4_ENABLE" == "1" ]]; then
              stage "net4_mode"
            else
              stage "net6_enable"
            fi
            ;;
          2) stage "net_iface" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_net4_mode
      net4_mode)
        rc=0
        ui_pick_net4_mode NET4_MODE || rc=$?
        case "$rc" in
          0)
            if [[ "$NET4_MODE" == "static" ]]; then
              stage "net_static"
            else
              stage "net6_enable"
            fi
            ;;
          2) stage "net_iface" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_net_static
      net_static)
        rc=0
        ui_pick_net4_static NET4_ADDR NET4_GW NET4_DNS || rc=$?
        case "$rc" in
          0) stage "net6_enable" ;;
          2) stage "net4_mode" ;;
          *) exit 0 ;;
        esac
        ;;

      net6_enable)
        rc=0
        ui_pick_net6_enable NET6_ENABLE || rc=$?
        case "$rc" in
          0)
            # нельзя выключить оба стека
            if [[ "${NET4_ENABLE:-1}" != "1" && "${NET6_ENABLE:-0}" != "1" ]]; then
              ui_msg "Нужно включить хотя бы один стек: IPv4 или IPv6."
              stage "net6_enable"
              continue
            fi

            if [[ "$NET6_ENABLE" == "1" ]]; then
              stage "net6_mode"
            else
              stage "hostname"
            fi
            ;;
          2)
            if [[ "${NET4_ENABLE:-1}" == "1" ]]; then
              # если IPv4 включён — назад в IPv4 (static -> net_static, иначе net4_mode)
              if [[ "${NET4_MODE:-dhcp}" == "static" ]]; then
                stage "net_static"
              else
                stage "net4_mode"
              fi
            else
              stage "net4_enable"
            fi
            ;;
          *) exit 0 ;;
        esac
        ;;


      net6_mode)
        rc=0
        ui_pick_net6_mode NET6_MODE || rc=$?
        case "$rc" in
          0)
            if [[ "$NET6_MODE" == "static" ]]; then
              stage "net6_static"
            else
              stage "hostname"
            fi
            ;;
          2) stage "net6_enable" ;;
          *) exit 0 ;;
        esac
        ;;

      net6_static)
        rc=0
        ui_pick_net6_static NET6_ADDR NET6_GW NET6_DNS || rc=$?
        case "$rc" in
          0) stage "hostname" ;;
          2) stage "net6_mode" ;;
          *) exit 0 ;;
        esac
        ;;

      # ui_hostname
      hostname)
        rc=0
        ui_pick_hostname HOSTNAME_SHORT || rc=$?
        case "$rc" in
          0) stage "hosts" ;;
          2)
            if [[ "${NET6_ENABLE:-0}" == "1" ]]; then
              if [[ "${NET6_MODE:-dhcp}" == "static" ]]; then
                stage "net6_static"
              else
                stage "net6_mode"
              fi
            elif [[ "${NET4_ENABLE:-1}" == "1" ]]; then
              if [[ "${NET4_MODE:-dhcp}" == "static" ]]; then
                stage "net_static"
              else
                stage "net4_mode"
              fi
            else
              stage "net6_enable"
            fi
            ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_hosts
      hosts)
        rc=0
        ui_pick_hosts HOSTS_DOMAIN HOSTS_FQDN "$HOSTNAME_SHORT" || rc=$?
        case "$rc" in
          0) stage "root_pass" ;;
          2) stage "hostname" ;;
          *) exit 0 ;;
        esac
        ;;
      # ui_root_pass
      root_pass)
        rc=0
        ui_pick_root_password ROOT_PASS || rc=$?
        case "$rc" in
          0)
            if validate_required_fields; then
              stage "summary"
            else
              stage "${REQUIRED_FIELDS_STAGE:-root_pass}"
            fi
            ;;
          2)
            if [[ "${NET6_ENABLE:-0}" == "1" ]]; then
              if [[ "${NET6_MODE:-dhcp}" == "static" ]]; then
                stage "net6_static"
              else
                stage "net6_mode"
              fi
            elif [[ "${NET4_ENABLE:-1}" == "1" ]]; then
              if [[ "${NET4_MODE:-dhcp}" == "static" ]]; then
                stage "net_static"
              else
                stage "net4_mode"
              fi
            else
              stage "net6_enable"
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
          2) stage "root_pass" ;;  # Назад -> на предыдущий шаг (поставь тот stage, который у тебя перед summary)
          *) exit 0 ;;
        esac
        ;;
      *) exit 1 ;;
    esac
  done
}


main "$@"
