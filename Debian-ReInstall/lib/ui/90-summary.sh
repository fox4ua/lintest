#!/usr/bin/env bash

# ui_confirm_summary
# return: 0=install/continue, 1=cancel/esc, 2=back
ui_confirm_summary() {
  local rc

  local net_block pass_line lvm_block msg

  local root_line
  if [[ "${ROOT_SIZE_GIB:-}" == "0" ]]; then
    root_line="disk space remaining"
  else
    root_line="${ROOT_SIZE_GIB:-} GiB"
  fi

  if [[ "${NET4_MODE:-dhcp}" == "static" ]]; then
    net_block=$(
      cat <<EOF
Mode: static
Iface: ${NET_IFACE:-}
Addr : ${NET4_ADDR:-}
GW   : ${NET4_GW:-}
DNS  : ${NET4_DNS:-}
EOF
    )
  else
    net_block=$(
      cat <<EOF
Mode: dhcp
Iface: ${NET_IFACE:-}
EOF
    )
  fi

  pass_line="not set"
  [[ -n "${ROOT_PASS:-}" ]] && pass_line="set"

  if [[ "${LVM_MODE:-none}" != "none" ]]; then
    lvm_block=$(
      cat <<EOF
LVM : ${LVM_MODE:-}
VG  : ${VG_NAME:-}
Thin: ${THINPOOL_NAME:-}
EOF
    )
  else
    lvm_block="LVM : none"
  fi

  msg=$(
    cat <<EOF
Debian : ${DEBIAN_VERSION:-} (${DEBIAN_SUITE:-})
Mirror : ${DEBIAN_MIRROR:-}

Boot   : ${BOOT_LABEL:-}
Disk   : ${DISK:-}

Partitions:
  /boot: ${BOOT_SIZE_MIB:-} MiB
  swap : ${SWAP_SIZE_GIB:-} GiB
  root : ${root_line:-}

${lvm_block}

Hostname: ${HOSTNAME_SHORT:-}
Domain  : ${HOSTS_DOMAIN:-}
FQDN    : ${HOSTS_FQDN:-}

Network:
${net_block}
Stack   : ${NET_STACK:-}

Root password: ${pass_line}
EOF
  )

  ui_dialog dialog --clear --cr-wrap \
    --title "Summary" \
    --yes-label "Установить" \
    --no-label "Отмена" \
    --help-button --help-label "Назад" \
    --yesno "$msg" 26 86
  rc=$?
  ui_clear

  case "$rc" in
    0) return 0 ;;      # Yes = Установить
    2) return 2 ;;      # Help = Назад
    1|255) return 1 ;;  # No/ESC = Отмена
    *) return 1 ;;
  esac
}
