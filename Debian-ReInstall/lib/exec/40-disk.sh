#!/usr/bin/env bash

disk_release_resources() {
  if (( DISK_NEEDS_RELEASE )) && (( ! DISK_RELEASE_APPROVED )); then
    fatal "Selected disk appears busy, but release was not approved in UI. Aborting."
  fi

  local disk="$DISK" base
  base="$(basename "$disk")"

  stage "release"
  log "[=] releasing resources on $disk"

  if command -v swapon >/dev/null 2>&1; then
    local s
    while IFS= read -r s; do
      [[ -n "$s" ]] || continue
      if [[ "$s" == "$disk"* ]]; then
        run_quiet swapoff "$s" || true
      fi
    done < <(swapon --show=NAME --noheadings 2>/dev/null | awk '{$1=$1;print}' || true)
  fi

  if command -v findmnt >/dev/null 2>&1; then
    local m
    while IFS= read -r m; do
      [[ -n "$m" ]] || continue
      run_quiet umount -f "$m" || true
    done < <(findmnt -nr -o TARGET -S "$disk"* 2>/dev/null | sort -r || true)
  fi

  if command -v pvs >/dev/null 2>&1 && command -v vgchange >/dev/null 2>&1; then
    local vg
    while IFS= read -r vg; do
      [[ -n "$vg" ]] || continue
      run_quiet vgchange -an "$vg" || true
    done < <(pvs --noheadings -o vg_name "$disk"* 2>/dev/null | awk '{$1=$1;print}' | sort -u || true)
  fi

  if command -v pvs >/dev/null 2>&1 && command -v vgremove >/dev/null 2>&1; then
    local vg
    while IFS= read -r vg; do
      [[ -n "$vg" ]] || continue
      run_quiet vgremove -ff "$vg" || true
    done < <(pvs --noheadings -o vg_name "$disk"* 2>/dev/null | awk '{$1=$1;print}' | sort -u || true)
  fi
  if command -v pvs >/dev/null 2>&1 && command -v pvremove >/dev/null 2>&1; then
    local pv
    while IFS= read -r pv; do
      [[ -n "$pv" ]] || continue
      run_quiet pvremove -ff "$pv" || true
    done < <(pvs --noheadings -o pv_name "$disk"* 2>/dev/null | awk '{$1=$1;print}' | sort -u || true)
  fi

  if [[ -r /proc/mdstat ]] && command -v mdadm >/dev/null 2>&1; then
    local md
    while IFS= read -r md; do
      [[ -n "$md" ]] || continue
      run_quiet mdadm --stop "/dev/$md" || true
    done < <(awk -v disk="$base" '$1 ~ /^md[0-9]+/ && $0 ~ disk {print $1}' /proc/mdstat || true)
  fi
}

disk_wipe() {
  stage "wipe"
  ui_msg "Marking disk $DISK.\n\nALL DATA WILL BE DESTROYED.\n\nLog: $LOG_FILE"
  run wipefs -a "$DISK" || true
  run dd if=/dev/zero of="$DISK" bs=1M count=10 conv=fsync || true

  local size_mib
  size_mib=$(( ($(blockdev --getsize64 "$DISK" 2>/dev/null || echo 0) / 1024 / 1024) ))
  if (( size_mib > 20 )); then
    run dd if=/dev/zero of="$DISK" bs=1M count=10 seek=$((size_mib - 10)) conv=fsync || true
  fi

  run sync
}

disk_partition() {
  stage "partition"
  local disk="$DISK"

  require_cmd parted || fatal "parted not found"

  local start_mib=1
  local cur_mib=$start_mib
  local end_mib p

  PART_EFI=""; PART_BIOS=""; PART_BOOT=""; PART_SWAP=""; PART_ROOT="";

  case "$BOOT_MODE" in
    uefi)
      run parted -s -a optimal "$disk" mklabel gpt
      end_mib=$((cur_mib + EFI_SIZE_MIB))
      run parted -s -a optimal "$disk" mkpart ESP fat32 "${cur_mib}MiB" "${end_mib}MiB"
      run parted -s "$disk" set 1 esp on
      PART_EFI="$(part_path "$disk" 1)"
      cur_mib=$end_mib
      end_mib=$((cur_mib + BOOT_SIZE_MIB))
      run parted -s -a optimal "$disk" mkpart boot ext4 "${cur_mib}MiB" "${end_mib}MiB"
      PART_BOOT="$(part_path "$disk" 2)"
      cur_mib=$end_mib
      p=3
      ;;
    biosgpt)
      run parted -s -a optimal "$disk" mklabel gpt
      end_mib=$((cur_mib + 2))
      run parted -s -a optimal "$disk" mkpart BIOSGRUB "${cur_mib}MiB" "${end_mib}MiB"
      run parted -s "$disk" set 1 bios_grub on
      PART_BIOS="$(part_path "$disk" 1)"
      cur_mib=$end_mib
      end_mib=$((cur_mib + BOOT_SIZE_MIB))
      run parted -s -a optimal "$disk" mkpart boot ext4 "${cur_mib}MiB" "${end_mib}MiB"
      PART_BOOT="$(part_path "$disk" 2)"
      cur_mib=$end_mib
      p=3
      ;;
    biosmbr|*)
      run parted -s -a optimal "$disk" mklabel msdos
      end_mib=$((cur_mib + BOOT_SIZE_MIB))
      run parted -s -a optimal "$disk" mkpart primary ext4 "${cur_mib}MiB" "${end_mib}MiB"
      PART_BOOT="$(part_path "$disk" 1)"
      cur_mib=$end_mib
      p=2
      ;;
  esac

  if (( SWAP_SIZE_GIB > 0 )); then
    local swap_mib=$((SWAP_SIZE_GIB * 1024))
    end_mib=$((cur_mib + swap_mib))
    run parted -s -a optimal "$disk" mkpart swap linux-swap "${cur_mib}MiB" "${end_mib}MiB"
    PART_SWAP="$(part_path "$disk" $p)"
    cur_mib=$end_mib
    p=$((p + 1))
  fi

  if (( ROOT_SIZE_GIB == 0 )); then
    run parted -s -a optimal "$disk" mkpart root ext4 "${cur_mib}MiB" 100%
  else
    local root_mib=$((ROOT_SIZE_GIB * 1024))
    end_mib=$((cur_mib + root_mib))
    run parted -s -a optimal "$disk" mkpart root ext4 "${cur_mib}MiB" "${end_mib}MiB"
  fi
  PART_ROOT="$(part_path "$disk" $p)"

  run partprobe "$disk" || true
  run_quiet udevadm settle || true

  log "[=] partitions: efi=$PART_EFI bios=$PART_BIOS boot=$PART_BOOT swap=$PART_SWAP root=$PART_ROOT"
}
