#!/usr/bin/env bash

ui_pick_iface() {
  local mode iface

  mode=$(dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Interface selection" \
    --radiolist "How to pick interface?" 12 74 4 \
      "auto" "Auto by default route" "on" \
      "manual" "Manual select" "off" \
    3>&1 1>&2 2>&3) || ui_abort

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

  local out
  out=$(dialog --clear \
    --backtitle "OVH VPS Rescue Installer" \
    --title "Network interface" \
    --radiolist "Select NIC:" 15 94 6 "${items[@]}" \
    3>&1 1>&2 2>&3) || ui_abort

  echo "$out"
}
