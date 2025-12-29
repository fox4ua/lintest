#!/usr/bin/env bash
set -Eeuo pipefail

ui_abort() {
  {
    stty sane < /dev/tty 2>/dev/null || true
    command -v tput >/dev/null 2>&1 && tput rmcup >/dev/tty 2>/dev/null || true
    printf '\033[?1049l\033[0m\033[H\033[2J' > /dev/tty 2>/dev/null || true
    clear > /dev/tty 2>/dev/null || true
  } || true
  echo "Canceled." > /dev/tty 2>/dev/null || true
  exit 0
}

ui_dialog_to_var() {
  local __outvar="$1"; shift
  local tmp rc __val=""

  tmp="$(mktemp)"

  dialog --clear --stdout "$@" </dev/tty 2>/dev/tty >"$tmp"
  rc=$?

  if [[ $rc -ne 0 ]]; then
    rm -f "$tmp"
    ui_abort
  fi

  if [[ -s "$tmp" ]]; then
    IFS= read -r __val <"$tmp"
  fi

  rm -f "$tmp"
  printf -v "$__outvar" '%s' "$__val"
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
