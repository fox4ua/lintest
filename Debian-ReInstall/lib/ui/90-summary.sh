#!/usr/bin/env bash

# ui_confirm_summary
# return: 0=Continue, 1=Cancel/ESC (exit), 2=Back
ui_confirm_summary() {
  local rc

  local net_block pass_line lvm_block msg

  local root_line
  if [[ "${ROOT_SIZE_GIB:-}" == "0" ]]; then
    root_line="disk space remaining"
  else
    root_line="${ROOT_SIZE_GIB:-} GiB"
  fi

  local net4_block net6_block
  if [[ "${NET4_ENABLE:-1}" == "1" ]]; then
    if [[ "${NET4_MODE:-dhcp}" == "static" ]]; then
      net4_block=$(
        cat <<EOF
IPv4:
  Mode: static
  Iface: ${NET_IFACE:-}
  Addr : ${NET4_ADDR:-}
  GW   : ${NET4_GW:-}
  DNS  : ${NET4_DNS:-}
EOF
      )
    else
      net4_block=$(
        cat <<EOF
IPv4:
  Mode: dhcp
  Iface: ${NET_IFACE:-}
EOF
      )
    fi
  else
    net4_block="IPv4: disabled"
  fi

  if [[ "${NET6_ENABLE:-0}" == "1" ]]; then
    if [[ "${NET6_MODE:-dhcp}" == "static" ]]; then
      net6_block=$(
        cat <<EOF
IPv6:
  Mode: static
  Iface: ${NET_IFACE:-}
  Addr : ${NET6_ADDR:-}
  GW   : ${NET6_GW:-}
  DNS  : ${NET6_DNS:-}
EOF
      )
    else
      net6_block=$(
        cat <<EOF
IPv6:
  Mode: dhcp
  Iface: ${NET_IFACE:-}
EOF
      )
    fi
  else
    net6_block="IPv6: disabled"
  fi

  net_block="${net4_block}
${net6_block}"


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
    --yes-label "Continue" \
    --no-label "Cancel" \
    --help-button --help-label "Back" \
    --yesno "$msg" 26 86
  rc=$?
  ui_clear

  case "$rc" in
    0) return 0 ;;      # Yes = Continue
    2) return 2 ;;      # Help = Back
    1|255) return 1 ;;  # No/ESC = Cancel
    *) return 1 ;;
  esac
}
