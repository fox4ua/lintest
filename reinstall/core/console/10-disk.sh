#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------
# print numbered menu
# -----------------------------
disk_menu_print() {
  local -n devs_ref="$1"
  local -n sizes_ref="$2"
  local -n models_ref="$3"
  local -n flags_ref="$4"
  local i

  echo
  echo "Select target disk:"
  echo "  #   DEV        SIZE   MODEL                     FLAGS"
  echo "  -----------------------------------------------------------"

  for ((i=0; i<${#devs_ref[@]}; i++)); do
    dev="${devs_ref[i]:-}"
    size="${sizes_ref[i]:-?}"
    model="${models_ref[i]:--}"
    flags_value="${flags_ref[i]:-}"

    printf "  %-3s %-10s %-6s %-24s %s\n" \
      "$((i+1))" "$dev" "$size" "$model" "$flags_value"
  done

  echo
}

# -----------------------------
# main public function: choose disk and write result into variable name
# -----------------------------
ui_pick_disk_console() {
  local out_var="$1"
  local -a devs=()
  local -a sizes=()
  local -a models=()
  local -a flags=()
  local choice idx dev

  while true; do
    if ! disk_menu_collect_candidates devs sizes models flags; then
      echo "ERROR: no disks detected or parsing failed."
      echo
      echo "DEBUG: raw disk_list_candidates output:"
      disk_list_candidates || true
      return 1
    fi

    disk_menu_print devs sizes models flags

    printf "Choose [1-%d, 0=Cancel]: " "${#devs[@]}"

    choice="$(disk_menu_read_choice_value "${#devs[@]}" || true)"
    [[ -n "$choice" ]] || { echo "Invalid choice. Try again."; continue; }

    if [[ "$choice" == "CANCEL" ]]; then
      return 1
    fi

    idx=$((choice - 1))
    dev="${devs[idx]}"

    if disk_menu_validate_and_explain "$dev"; then
      printf -v "$out_var" '%s' "$dev"
      return 0
    fi
  done
}
