#!/usr/bin/env bash
set -Eeuo pipefail

ui_center_block() {
  local width="${1:?width}"; shift
  local text="${1-}"
  local out="" line len pad

  while IFS= read -r line; do
    # пустую строку оставляем пустой
    if [[ -z "$line" ]]; then
      out+=$'\n'
      continue
    fi

    len=${#line}
    if (( len >= width )); then
      out+="${line}"$'\n'
    else
      pad=$(( (width - len) / 2 ))
      out+="$(printf '%*s%s\n' "$pad" "" "$line")"
    fi
  done <<< "$text"

  printf '%s' "$out"
}

ui_welcome() {
  local _boot_mode="${1-}" # параметр оставляем, но не показываем

  local msg
  msg=$(
    cat <<EOF
RUN ONLY IN RESCUE MODE.

All data will be destroyed.

Log: ${LOG_FILE}
EOF
  )

  dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Welcome" \
    --no-collapse --cr-wrap \
    --yes-label "Continue" \
    --no-label "Cancel" \
    --yesno "$(ui_center_block 62 "$msg")" 12 74

  # 0 = Yes, 1 = No, 255 = ESC
  case $? in
    0) return 0 ;;
    *) die "Canceled by user." ;;
  esac
}






boot_mode_human() {
  case "${1:-}" in
    uefi) echo "UEFI" ;;
    bios) echo "Legacy (BIOS/CSM)" ;;
    *) echo "$1" ;;
  esac
}

ui_pick_boot_mode() {
  local detected="$1"
  local default_key="auto"

  # Pick default selection in dialog
  # If detected is uefi, make "auto" still default but show detected in text.
  # (Keeping "auto" as default reduces accidental mismatch.)
  local auto_on="on" uefi_on="off" bios_on="off"

  local pick
  pick=$(dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Boot mode" \
    --radiolist "Detected (heuristic): $(boot_mode_human "$detected")\n\nChoose boot mode for installation:" 14 74 4 \
      "auto" "Use detected ($(boot_mode_human "$detected"))" "${auto_on}" \
      "uefi" "Force UEFI (ESP + grub-efi)" "${uefi_on}" \
      "bios" "Force Legacy (BIOS/CSM) (bios_grub + grub-pc)" "${bios_on}" \
    3>&1 1>&2 2>&3)

  case "$pick" in
    auto|"")
      echo "$detected"
      ;;

    uefi)
      if ! has_uefi_rescue; then
        dialog --clear \
          --backtitle "OVH VPS Rescue Installer" \
          --title "Warning: UEFI not detected in Rescue" \
          --yesno \
"You selected FORCE UEFI, but this Rescue environment does NOT expose UEFI (/sys/firmware/efi is missing).

On many VPS this means UEFI boot may NOT be available, and the installed system could become unbootable.

Continue forcing UEFI anyway?" 15 86
        if [[ $? -ne 0 ]]; then
          # user chose "No" -> fallback to detected
          echo "$detected"
          return 0
        fi
      fi
      echo "uefi"
      ;;

    bios)
      if has_uefi_rescue; then
        dialog --clear \
          --backtitle "OVH VPS Rescue Installer" \
          --title "Warning: UEFI detected in Rescue" \
          --yesno \
"You selected FORCE Legacy (BIOS/CSM), but this Rescue environment exposes UEFI.

If the VPS is configured to boot only in UEFI mode, Legacy (BIOS/CSM) installation may not boot.

Continue forcing Legacy (BIOS/CSM) anyway?" 14 86
        if [[ $? -ne 0 ]]; then
          # user chose "No" -> fallback to detected
          echo "$detected"
          return 0
        fi
      fi
      echo "bios"
      ;;

    *)
      die "Invalid boot mode selection: $pick"
      ;;
  esac
}



has_uefi_rescue() {
  [[ -d /sys/firmware/efi ]]
}



ui_pick_disk() {
  local items=()
  while read -r name size type; do
    [[ "$type" != "disk" ]] && continue
    items+=("/dev/$name" "/dev/$name ($size)" "off")
  done < <(lsblk -dn -o NAME,SIZE,TYPE)

  (( ${#items[@]} > 0 )) || die "No disks found."
  items[2]="on"
  dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Select target disk (WILL BE WIPED)"     --radiolist "Choose disk:" 15 78 6 "${items[@]}" 3>&1 1>&2 2>&3
}

ui_pick_swap() {
  dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Swap size"     --radiolist "Select swap size:" 12 60 4     "1" "1 GB" "on" "2" "2 GB" "off" "4" "4 GB" "off" 3>&1 1>&2 2>&3
}

ui_pick_boot() {
  dialog --clear --backtitle "OVH VPS Rescue Installer" --title "/boot size"     --radiolist "Select /boot size:" 13 70 5     "min" "Minimal 512 MB" "on"     "mid" "Medium 1 GB" "off"     "max" "Maximum 2 GB" "off" 3>&1 1>&2 2>&3
}

boot_label_to_mib() { case "$1" in min) echo 512;; mid) echo 1024;; max) echo 2048;; *) die "bad /boot size";; esac; }

ui_pick_lvm_mode() {
  dialog --clear --backtitle "OVH VPS Rescue Installer" --title "LVM mode"     --radiolist "Select LVM mode:" 12 74 4     "linear" "Classic LVM (linear)" "on"     "thin"   "LVM-thin (thin pool)" "off" 3>&1 1>&2 2>&3
}

ui_input_root_size() {
  local v
  v=$(dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Root size"     --inputbox "Root size in GB (default 30):" 10 60 "30" 3>&1 1>&2 2>&3)
  [[ "$v" =~ ^[0-9]+$ ]] || die "Root size must be integer"
  echo "$v"
}

ui_pick_debian() {
  dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Debian version"     --radiolist "Select Debian release:" 14 78 5     "trixie" "Debian 13 (trixie)" "on"     "bookworm" "Debian 12 (bookworm)" "off"     "bullseye" "Debian 11 (bullseye)" "off" 3>&1 1>&2 2>&3
}

ui_pick_mirror() {
  dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Debian mirror"     --radiolist "Select mirror:" 12 86 3     "http://deb.debian.org/debian" "deb.debian.org (recommended)" "on"     "http://ftp.de.debian.org/debian" "ftp.de.debian.org" "off"     "http://ftp.fr.debian.org/debian" "ftp.fr.debian.org" "off" 3>&1 1>&2 2>&3
}

ui_input_hostname() {
  dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Hostname"     --inputbox "Hostname (default pve):" 10 60 "pve" 3>&1 1>&2 2>&3
}

ui_pick_iface() {
  local mode iface
  mode=$(dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Interface selection"     --radiolist "How to pick interface?" 12 74 4     "auto" "Auto by default route" "on"     "manual" "Manual select" "off" 3>&1 1>&2 2>&3)

  if [[ "$mode" == "auto" ]]; then
    iface="$(ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' || true)"
    [[ -n "$iface" ]] && { echo "$iface"; return 0; }
  fi

  local items=()
  while read -r ifn state rest; do
    [[ "$ifn" == "lo" ]] && continue
    items+=("$ifn" "$state $rest" "off")
  done < <(ip -br link)
  (( ${#items[@]} > 0 )) || die "No interfaces found."
  items[2]="on"
  dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Network interface"     --radiolist "Select NIC:" 15 94 6 "${items[@]}" 3>&1 1>&2 2>&3
}

ui_pick_net_backend() {
  dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Network backend"     --radiolist "Choose how to configure network in target:" 13 86 4     "ifupdown" "ifupdown (/etc/network/interfaces)" "on"     "networkd" "systemd-networkd (recommended for new Debian)" "off"     3>&1 1>&2 2>&3
}

ui_pick_net_mode() {
  dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Network mode"     --radiolist "Network config:" 12 72 4     "dhcp" "DHCP" "on"     "static" "Static IPv4" "off" 3>&1 1>&2 2>&3
}

ui_pick_static_profile() {
  dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Static profile"     --radiolist "Static mode profile:" 14 92 6     "ovh32" "OVH /32 + gateway onlink (common OVH VPS)" "on"     "generic" "Generic static (CIDR + gateway)" "off"     3>&1 1>&2 2>&3
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

ui_input_static() {
  local profile="$1"
  if [[ "$profile" == "ovh32" ]]; then
    local ip gw dns gw_def dns_def
    gw_def="$(ui_guess_default_gw)"
    dns_def="$(ui_guess_dns_list)"

    ip=$(dialog --clear --backtitle "OVH VPS Rescue Installer" --title "OVH static (/32)"       --inputbox "IPv4 address (no /32, e.g. 203.0.113.10):" 10 86 "" 3>&1 1>&2 2>&3)

    gw=$(dialog --clear --backtitle "OVH VPS Rescue Installer" --title "OVH static (/32)"       --inputbox "Gateway (suggested from Rescue default route):" 10 86 "${gw_def}" 3>&1 1>&2 2>&3)

    dns=$(dialog --clear --backtitle "OVH VPS Rescue Installer" --title "OVH static (/32)"       --inputbox "DNS (space separated; suggested from Rescue resolv.conf):" 10 92 "${dns_def}" 3>&1 1>&2 2>&3)

    echo "${ip}|${gw}|${dns}"
  else
    local ipcidr gw dns gw_def dns_def
    gw_def="$(ui_guess_default_gw)"
    dns_def="$(ui_guess_dns_list)"

    ipcidr=$(dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Static IPv4"       --inputbox "IP/CIDR (e.g. 203.0.113.10/24):" 10 86 "" 3>&1 1>&2 2>&3)

    gw=$(dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Static IPv4"       --inputbox "Gateway (suggested from Rescue default route):" 10 86 "${gw_def}" 3>&1 1>&2 2>&3)

    dns=$(dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Static IPv4"       --inputbox "DNS (space separated; suggested from Rescue resolv.conf):" 10 92 "${dns_def}" 3>&1 1>&2 2>&3)

    echo "${ipcidr}|${gw}|${dns}"
  fi
}

ui_input_root_password() {
  local p1 p2
  while true; do
    p1=$(dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Root password"       --insecure --passwordbox "Enter root password:" 10 60 3>&1 1>&2 2>&3)
    p2=$(dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Root password"       --insecure --passwordbox "Confirm:" 10 60 3>&1 1>&2 2>&3)
    [[ -n "$p1" && "$p1" == "$p2" && ${#p1} -ge 8 ]] && { echo "$p1"; return 0; }
    dialog --msgbox "Password mismatch / too short (min 8)." 7 48
  done
}

ui_confirm_or_exit() {
  dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Confirm"     --yesno "Proceed with DISK WIPE and reinstall?" 8 50
}

ui_done_and_reboot() {
  local boot_mode="$1" lvm_mode="$2" net_mode="$3" iface="$4" backend="$5"
  dialog --clear --backtitle "OVH VPS Rescue Installer" --title "Done" --msgbox "Completed.

Boot: $(boot_mode_human "$boot_mode")
LVM:  ${lvm_mode}
Net:  ${net_mode} (${iface})
Cfg:  ${backend}

1) Reboot
2) Disable Rescue mode in OVH panel (boot from disk)
3) SSH as root with chosen password

Log: ${LOG_FILE}" 20 90
  clear
  reboot
}
