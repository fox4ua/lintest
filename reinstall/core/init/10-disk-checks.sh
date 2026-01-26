#!/usr/bin/env bash
set -Eeuo pipefail


if ! declare -F log >/dev/null; then
  log() { printf '%s\n' "$*" >&2; }
fi

disk_resolve_parent_disk() {
  local node="$1"
  local base parent type guard=0

  node="$(readlink -f "$node" 2>/dev/null || echo "$node")"

  command -v lsblk >/dev/null 2>&1 || return 1

  while (( guard < 16 )); do
    base="$(basename "$node")"
    type="$(lsblk -no TYPE "$node" 2>/dev/null | head -n1 || true)"
    if [[ "$type" == "disk" ]]; then
      printf '%s\n' "$base"
      return 0
    fi

    parent="$(lsblk -no PKNAME "$node" 2>/dev/null | head -n1 || true)"
    [[ -n "$parent" ]] || break
    node="/dev/$parent"
    ((guard++))
  done

  return 1
}

disk_is_current_env_disk() {
  local disk="$1"
  local src base resolved

  base="$(basename "$disk")"

  for src in / /boot /boot/efi; do
    src="$(findmnt -no SOURCE "$src" 2>/dev/null || true)"
    [[ -n "$src" ]] || continue

    if [[ "$src" == "$disk"* ]]; then
      return 0
    fi

    if resolved="$(disk_resolve_parent_disk "$src")"; then
      [[ "$resolved" == "$base" ]] && return 0
    fi
  done

  return 1
}

disk_list_candidates() {
  command -v lsblk >/dev/null 2>&1 || return 1

  local -a items=()
  while IFS= read -r line; do
    local name type size model
    name="$(awk '{print $1}' <<<"$line")"
    type="$(awk '{print $2}' <<<"$line")"
    size="$(awk '{print $3}' <<<"$line")"
    model="$(cut -d' ' -f4- <<<"$line")"

    [[ "$type" == "disk" ]] || continue

    local dev="/dev/$name"
    [[ -b "$dev" ]] || continue

    [[ -n "$model" ]] || model="-"
    items+=("${dev}" "${size}" "${model}")
  done < <(lsblk -dn -o NAME,TYPE,SIZE,MODEL 2>/dev/null | sed 's/[[:space:]]\+/ /g')

  [[ ${#items[@]} -gt 0 ]] || return 1

  local i
  for ((i = 0; i < ${#items[@]}; i += 3)); do
    printf '%s\t%s\t%s\n' "${items[i]}" "${items[i+1]}" "${items[i+2]}"
  done
}

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

# Флаги (глобальные) — как в вашем коде
disk_detect_usage_flags() {
  local disk="$1"
  DISK_HAS_MOUNTS=0
  DISK_HAS_SWAP=0
  DISK_HAS_LVM=0
  DISK_HAS_MD=0
  DISK_NEEDS_RELEASE=0
  DISK_DETECT_INCOMPLETE=0

  local parts

  if command -v lsblk >/dev/null 2>&1; then
    parts="$(lsblk -ln -o PATH "$disk" 2>/dev/null | tail -n +2 || true)"
  else
    DISK_DETECT_INCOMPLETE=1
    log "[!] disk detect: lsblk not found, disk usage check incomplete"
    echo "Warning: lsblk not found, disk usage check incomplete." >&2
    parts=""
  fi

  # mounts
  if command -v findmnt >/dev/null 2>&1; then
    if [[ -n "$parts" ]]; then
      while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        if findmnt -nr -S "$p" >/dev/null 2>&1; then
          DISK_HAS_MOUNTS=1
          DISK_NEEDS_RELEASE=1
          break
        fi
      done <<<"$parts"
    fi
  else
    DISK_DETECT_INCOMPLETE=1
    log "[!] disk detect: findmnt not found, mount check skipped"
    echo "Warning: findmnt not found, mount check skipped." >&2
  fi

  # swap
  if command -v swapon >/dev/null 2>&1; then
    while IFS= read -r s; do
      [[ -n "$s" ]] || continue
      if [[ "$s" == "$disk"* ]]; then
        DISK_HAS_SWAP=1
        DISK_NEEDS_RELEASE=1
        break
      fi
    done < <(swapon --show=NAME --noheadings 2>/dev/null | awk '{$1=$1;print}' || true)
  else
    DISK_DETECT_INCOMPLETE=1
    log "[!] disk detect: swapon not found, swap check skipped"
    echo "Warning: swapon not found, swap check skipped." >&2
  fi

  # lvm pv
  if command -v pvs >/dev/null 2>&1; then
    while IFS= read -r pv; do
      [[ -n "$pv" ]] || continue
      if [[ "$pv" == "$disk"* ]]; then
        DISK_HAS_LVM=1
        DISK_NEEDS_RELEASE=1
        break
      fi
    done < <(pvs --noheadings -o pv_name 2>/dev/null | awk '{$1=$1;print}' || true)
  else
    DISK_DETECT_INCOMPLETE=1
    log "[!] disk detect: pvs not found, LVM check skipped"
    echo "Warning: pvs not found, LVM check skipped." >&2
  fi

  # md
  if [[ -r /proc/mdstat ]]; then
    local base
    base="$(basename "$disk")"
    if grep -q "$base" /proc/mdstat; then
      DISK_HAS_MD=1
      DISK_NEEDS_RELEASE=1
    fi
  fi
}

disk_usage_summary() {
  local msg=()
  [[ "${DISK_HAS_MOUNTS:-0}" -eq 1 ]] && msg+=("mounts")
  [[ "${DISK_HAS_SWAP:-0}" -eq 1 ]] && msg+=("swap")
  [[ "${DISK_HAS_LVM:-0}" -eq 1 ]] && msg+=("lvm")
  [[ "${DISK_HAS_MD:-0}" -eq 1 ]] && msg+=("mdraid")
  [[ "${DISK_DETECT_INCOMPLETE:-0}" -eq 1 ]] && msg+=("incomplete-detect")

  if [[ ${#msg[@]} -eq 0 ]]; then
    printf '%s\n' "clean"
  else
    (IFS=','; printf '%s\n' "${msg[*]}")
  fi
}

# Универсальная проверка выбранного диска
# Возвраты:
#   0 = ok
#   2 = нельзя выбирать (текущая среда)
#   3 = диск занят (mount/swap/lvm/md) -> можно запретить или показывать предупреждение
#   1 = некорректно
disk_validate_choice() {
  local disk="$1"
  [[ -n "$disk" && -b "$disk" ]] || return 1

  if disk_is_current_env_disk "$disk"; then
    return 2
  fi

  disk_detect_usage_flags "$disk"
  if [[ "${DISK_NEEDS_RELEASE:-0}" -eq 1 ]]; then
    return 3
  fi

  return 0
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

has_space_for_data_fs() {
  local disk="$1"
  local root_size="$2"
  local boot_mode="${3:-bios}"
  local efi_size="${4:-256}"
  local boot_size="${5:-512}"
  local swap_size="${6:-0}"
  local min_data_gb="${7:-1}"

  local disk_bytes root_bytes reserved_bytes free_bytes min_data_bytes

  disk_bytes="$(disk_size_bytes "$disk" 2>/dev/null || true)"
  if [[ -z "$disk_bytes" || ! "$disk_bytes" =~ ^[0-9]+$ || "$disk_bytes" -le 0 ]]; then
    return 1
  fi

  root_bytes="$(root_gb_to_bytes "$root_size" 2>/dev/null || true)"
  if [[ -z "$root_bytes" || ! "$root_bytes" =~ ^[0-9]+$ || "$root_bytes" -le 0 ]]; then
    return 1
  fi

  reserved_bytes="$(calc_reserved_bytes "$boot_mode" "$efi_size" "$boot_size" "$swap_size" 2>/dev/null || true)"
  if [[ -z "$reserved_bytes" || ! "$reserved_bytes" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  free_bytes=$(( disk_bytes - reserved_bytes - root_bytes ))
  if (( free_bytes < 0 )); then
    free_bytes=0
  fi

  min_data_bytes=$(( min_data_gb * 1024 * 1024 * 1024 ))
  if (( free_bytes >= min_data_bytes )); then
    return 0
  fi

  return 1
}
