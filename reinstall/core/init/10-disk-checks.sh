#!/usr/bin/env bash
set -Eeuo pipefail

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
