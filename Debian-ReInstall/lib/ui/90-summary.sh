#!/usr/bin/env bash

# ui_confirm_summary
# return: 0=install/continue, 1=cancel/esc, 2=back
ui_confirm_summary() {
  local rc

  local net_line=""
  if [[ "${NET_MODE:-dhcp}" == "static" ]]; then
    net_line="Mode: static\nIface: ${NET_IFACE:-}\nAddr: ${NET_ADDR:-}\nGW: ${NET_GW:-}\nDNS: ${NET_DNS:-}"
  else
    net_line="Mode: dhcp\nIface: ${NET_IFACE:-}"
  fi

  local pass_line="not set"
  [[ -n "${ROOT_PASS:-}" ]] && pass_line="set"

  # LVM строка (если ты включал LVM)
  local lvm_line="LVM: ${LVM_MODE:-none}"
  if [[ "${LVM_MODE:-none}" != "none" ]]; then
    lvm_line="${lvm_line}\nVG: ${VG_NAME:-}\nThinpool: ${THINPOOL_NAME:-}"
  fi

  ui_dialog dialog --clear \
    --title "Summary" \
    --ok-label "Установить" \
    --cancel-label "Отмена" \
    --help-button --help-label "Назад" \
    --yesno \
"Debian: ${DEBIAN_VERSION:-} (${DEBIAN_SUITE:-})
Mirror: ${DEBIAN_MIRROR:-}

Boot: ${BOOT_LABEL:-}
Disk: ${DISK:-}
Partitions:
  /boot: ${BOOT_SIZE_MIB:-} MiB
  swap : ${SWAP_SIZE_GIB:-} GiB
  root : ${ROOT_SIZE_GIB:-} GiB (0=остаток)

${lvm_line}

Hostname: ${HOSTNAME_SHORT:-}
Domain: ${HOSTS_DOMAIN:-}
FQDN: ${HOSTS_FQDN:-}

Network:
${net_line}

Network stack: ${NET_STACK:-}
Root password: ${pass_line}
" 24 74
  rc=$?
  ui_clear

  case "$rc" in
    0) return 0 ;;   # OK = install
    2) return 2 ;;   # HELP = back
    1|255) return 1 ;; # cancel/esc
    *) return 1 ;;
  esac
}
