#!/usr/bin/env bash
set -Eeuo pipefail

ui_abort() {
  clear
  stty sane 2>/dev/null || true
  echo "Canceled."
  exit 0
}

# Helpers (non-window)
has_uefi_rescue() {
  [[ -d /sys/firmware/efi ]]
}

boot_label_to_mib() {
  case "$1" in
    min) echo 512 ;;
    mid) echo 1024 ;;
    max) echo 2048 ;;
    *) die "bad /boot size" ;;
  esac
}

ui_guess_default_gw() {
  local gw
  gw="$(ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}' || true)"
  [[ -n "$gw" ]] && { echo "$gw"; return 0; }
  echo "169.254.0.1"
}

ui_guess_dns_list() {
  local dns
  dns="$(awk '/^nameserver[[:space:]]+/ {print $2}' /etc/resolv.conf 2>/dev/null | paste -sd' ' - || true)"
  [[ -n "$dns" ]] && { echo "$dns"; return 0; }
  echo "1.1.1.1 8.8.8.8"
}
