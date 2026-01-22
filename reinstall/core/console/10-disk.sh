#!/usr/bin/env bash
set -Eeuo pipefail

# Ожидается, что эти функции уже доступны:
# disk_list_candidates
# disk_is_current_env_disk
# disk_detect_usage_flags
# disk_usage_summary
# disk_validate_choice
# shellcheck source=/dev/null
source "$BASE_DIR/init/10-disk-checks.sh"

# -----------------------------
# parse one line from disk_list_candidates into: dev size model
# supports TAB-separated or space-separated formats
# -----------------------------
disk_menu_parse_candidate_line() {
  local line="$1"
  local dev="" size="" model=""

  # 1) TAB-separated: /dev/sda<TAB>100G<TAB>MODEL...
  IFS=$'\t' read -r dev size model <<<"$line"

  # 2) Space-separated: /dev/sda 100G MODEL...
  if [[ -z "${size:-}" ]]; then
    read -r dev size <<<"$line"
    if [[ -n "$dev" && -n "$size" ]]; then
      model="${line#"$dev"}"
      model="${model#"$size"}"
      model="$(echo "$model" | sed 's/^[[:space:]]\+//')"
      [[ -n "$model" ]] || model="-"
    fi
  fi

  [[ -n "$dev" ]] || return 1
  printf '%s\t%s\t%s\n' "$dev" "${size:-?}" "${model:--}"
}

# -----------------------------
# build flags for a device (CURRENT-ENV or usage summary)
# -----------------------------
disk_menu_build_flags() {
  local dev="$1"
  local flags_value=""

  if disk_is_current_env_disk "$dev"; then
    printf '%s\n' "CURRENT-ENV"
    return 0
  fi

  disk_detect_usage_flags "$dev"
  flags_value="$(disk_usage_summary)"

  printf '%s\n' "$flags_value"
}

# -----------------------------
# collect candidates into arrays: devs/sizes/models/flags
# -----------------------------
disk_menu_collect_candidates() {
  local -n devs_ref="$1"
  local -n sizes_ref="$2"
  local -n models_ref="$3"
  local -n flags_ref="$4"

  local line parsed dev size model flags_value

  devs_ref=()
  sizes_ref=()
  models_ref=()
  flags_ref=()

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue

    parsed="$(disk_menu_parse_candidate_line "$line" 2>/dev/null || true)"
    [[ -n "$parsed" ]] || continue

    IFS=$'\t' read -r dev size model <<<"$parsed"

    flags_value="$(disk_menu_build_flags "$dev" | tr -d '\r\n')"
    [[ -n "$flags_value" ]] || flags_value="clean"

    devs_ref+=("$dev")
    sizes_ref+=("$size")
    models_ref+=("$model")
    flags_ref+=("$flags_value")
  done < <(disk_list_candidates 2>/dev/null || true)

  [[ ${#devs_ref[@]} -gt 0 ]] || return 1
}

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
# read numeric choice; echoes:
#   - "CANCEL" for 0
#   - index (0-based) for valid choice
# returns non-zero if invalid input
# -----------------------------
disk_menu_read_choice_value() {
  local max="$1"
  local ans

  read -r ans

  [[ -n "$ans" ]] || return 1
  [[ "$ans" =~ ^[0-9]+$ ]] || return 1

  if [[ "$ans" -eq 0 ]]; then
    echo "CANCEL"
    return 0
  fi

  if (( ans < 1 || ans > max )); then
    return 1
  fi

  echo "$ans"
  return 0
}

# -----------------------------
# validate chosen disk and return:
#   0 -> ok
#   2 -> current env disk
#   3 -> busy
#   1 -> invalid
# prints message for the user and returns same code
# -----------------------------
disk_menu_validate_and_explain() {
  local dev="$1"
  local rc=0

  disk_validate_choice "$dev" || rc=$?

  case "$rc" in
    0) return 0 ;;
    2)
      echo "This disk is used by the current environment. Choose another."
      return 2
      ;;
    3)
      disk_detect_usage_flags "$dev"
      echo "Disk is in use: $(disk_usage_summary)"
      echo "Choose another disk."
      return 3
      ;;
    *)
      echo "Invalid disk selection."
      return 1
      ;;
  esac
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
