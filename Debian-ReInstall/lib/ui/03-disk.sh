#!/usr/bin/env bash

# предупреждение, выбран системный диск
# return: 2=Back, 1=Cancel/ESC
ui_block_current_env_disk() {
  local disk="$1"
  local rc
  local src_root
  src_root="$(findmnt -no SOURCE / 2>/dev/null || true)"
  msg=$(
    cat <<EOF
This disc is used by the current environment.

Current / mounted from:
${src_root:-unknown}

Selected disc: ${disk}

Choose another disc.
EOF
  )

  ui_dialog dialog --clear \
    --title "This disc cannot be selected" \
    --yes-label "Back" \
    --no-label "Cancel" \
    --yesno "$msg" 14 74
  rc=$?
  ui_clear
  case "$rc" in
    0|2) return 2 ;;     # YES = Назад
    1|255) return 1 ;;   # NO/ESC = Отмена
    *) return 1 ;;
  esac
}

# предупреждение, разделы выбранного диска сущестуют и смонтированы
# return: 0=Continue, 2=Back, 1=Cancel/ESC
ui_warn_disk_busy_plan_only() {
  local disk="$1"
  local text="Active resources found on the selected drive.\n\nDrive: $disk\n\n"
  (( DISK_HAS_MOUNTS )) && text+="• There are mounted partitions\n"
  (( DISK_HAS_SWAP   )) && text+="• There is an active swap\n"
  (( DISK_HAS_LVM    )) && text+="• There is LVM PV\n"
  (( DISK_HAS_MD     )) && text+="• Possibly mdraid\n"
  text+="\nThey will be disabled before marking."

  ui_dialog dialog --clear \
    --title "Disc is used" \
    --yes-label "Continue" \
    --no-label "Cancel" \
    --help-button \
    --help-label "Back" \
    --yesno "$text" 16 74
  local rc=$?
  ui_clear

  case "$rc" in
    0) return 0 ;;
    2) return 2 ;;
    *) return 1 ;;
  esac
}

# окно выбора диска
# return: 0=Select, 2=Back, 1=Cancel/ESC
ui_pick_disk() {
  local out_disk="$1"
  local choice rc warn_rc
  local -a items=()

  # собираем /dev/sdX, /dev/nvme0n1 и т.п.
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
    items+=("$dev" "${size}  ${model}")
  done < <(lsblk -dn -o NAME,TYPE,SIZE,MODEL 2>/dev/null | sed 's/[[:space:]]\+/ /g')

  if [[ ${#items[@]} -eq 0 ]]; then
    ui_msg "No available disks found (lsblk returned empty)."
    return 1
  fi

  while true; do
    choice="$(
      ui_dialog dialog --clear --stdout \
        --title "Choosing a disc" \
        --ok-label "Select" \
        --cancel-label "Cancel" \
        --help-button \
        --help-label "Back" \
        --menu "Select the disk for installation (ALL DATA WILL BE DELETED)):" 18 74 10 \
        "${items[@]}"
    )"
    rc=$?
    ui_clear

    case "$rc" in
      0) : ;;
      2) return 2 ;;         # Back
      1|255) return 1 ;;     # Cancel/ESC
      *) return 1 ;;
    esac

    [[ -b "$choice" ]] || continue

    # Блокирующая проверка "системного диска" (как реализовано в текущем архиве)
    # Блокирующая проверка: выбран диск текущей среды (rescue/live)
    if disk_is_current_env_disk "$choice"; then
      ui_block_current_env_disk "$choice"
      case $? in
        2) continue ;;  # назад -> снова список дисков
        *) return 1 ;;  # отмена/esc
      esac
    fi

    # Проверка занятости диска (mount/swap/lvm/md) и предложение "освободить"
    # Только детект и запись флагов (действия будут потом, на стадии установки)
    DISK_RELEASE_APPROVED=0
    disk_detect_usage_flags "$choice"

    if (( DISK_NEEDS_RELEASE )); then
      ui_warn_disk_busy_plan_only "$choice"
      case $? in
        0) DISK_RELEASE_APPROVED=1 ;;  # пользователь согласен “отключить позже”
        2) continue ;;                 # назад -> снова список дисков
        *) return 1 ;;                 # отмена/esc
      esac
    fi

    printf -v "$out_disk" "%s" "$choice"
    return 0
  done
}


