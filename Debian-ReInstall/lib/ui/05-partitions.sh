#!/usr/bin/env bash

# ui_pick_partition_sizes OUT_BOOT_MIB OUT_SWAP_GIB OUT_ROOT_GIB DISK
# return: 0=ok, 1=cancel/esc, 2=back
ui_pick_partition_sizes() {
  local out_boot="$1"
  local out_swap="$2"
  local out_root="$3"
  local disk="$4"

  local rc=0 boot_mib swap_gib root_gib

  # Берём текущие значения из env (или дефолты)
  boot_mib="${BOOT_SIZE_MIB:-512}"
  swap_gib="${SWAP_SIZE_GIB:-1}"
  root_gib="${ROOT_SIZE_GIB:-30}"

  # Узнаем размер диска (GiB, округление вниз) — только для подсказок
  local disk_gib=""
  disk_gib="$(lsblk -dn -b -o SIZE "$disk" 2>/dev/null | awk '{printf "%.0f", $1/1024/1024/1024}' || true)"
  [[ -n "$disk_gib" ]] || disk_gib="unknown"

  # 1) /boot
  rc=0
  boot_mib="$(
    ui_dialog dialog --clear --stdout \
      --title "/boot" \
      --ok-label "Далее" \
      --cancel-label "Отмена" \
      --help-button --help-label "Назад" \
      --menu "Выберите размер /boot (диск: $disk, ${disk_gib}GiB):" 15 74 6 \
        256  "256 MiB (минимально)" \
        512  "512 MiB (рекомендуется)" \
        1024 "1024 MiB" \
        2048 "2048 MiB" \
        custom "Ввести вручную"
  )"
  rc=$?
  ui_clear
  case "$rc" in
    0) : ;;
    2) return 2 ;;
    1|255) return 1 ;;
    *) return 1 ;;
  esac

  if [[ "$boot_mib" == "custom" ]]; then
    boot_mib="$(
      ui_dialog dialog --clear --stdout \
        --title "/boot" \
        --ok-label "Далее" \
        --cancel-label "Отмена" \
        --help-button --help-label "Назад" \
        --inputbox "Введите размер /boot в MiB (например 512):" 10 74 "$boot_mib"
    )"
    rc=$?
    ui_clear
    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac
  fi

  # валидация /boot
  if ! [[ "$boot_mib" =~ ^[0-9]+$ ]] || (( boot_mib < 128 || boot_mib > 8192 )); then
    ui_msg "Некорректный размер /boot: $boot_mib\n\nДопустимо: 128..8192 MiB."
    return 2
  fi

  # 2) swap
  rc=0
  swap_gib="$(
    ui_dialog dialog --clear --stdout \
      --title "swap" \
      --ok-label "Далее" \
      --cancel-label "Отмена" \
      --help-button --help-label "Назад" \
      --menu "Выберите размер swap:" 15 74 7 \
        0   "Без swap" \
        1   "1 GiB" \
        2   "2 GiB" \
        4   "4 GiB" \
        8   "8 GiB" \
        16  "16 GiB" \
        custom "Ввести вручную"
  )"
  rc=$?
  ui_clear
  case "$rc" in
    0) : ;;
    2) return 2 ;;
    1|255) return 1 ;;
    *) return 1 ;;
  esac

  if [[ "$swap_gib" == "custom" ]]; then
    swap_gib="$(
      ui_dialog dialog --clear --stdout \
        --title "swap" \
        --ok-label "Далее" \
        --cancel-label "Отмена" \
        --help-button --help-label "Назад" \
        --inputbox "Введите размер swap в GiB (0 = без swap):" 10 74 "$swap_gib"
    )"
    rc=$?
    ui_clear
    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac
  fi

  # валидация swap
  if ! [[ "$swap_gib" =~ ^[0-9]+$ ]] || (( swap_gib < 0 || swap_gib > 512 )); then
    ui_msg "Некорректный размер swap: $swap_gib\n\nДопустимо: 0..512 GiB."
    return 2
  fi

  # 3) root
  rc=0
  root_gib="$(
    ui_dialog dialog --clear --stdout \
      --title "root" \
      --ok-label "Готово" \
      --cancel-label "Отмена" \
      --help-button --help-label "Назад" \
      --menu "Выберите размер root (/):" 16 74 8 \
        20  "20 GiB" \
        30  "30 GiB (по умолчанию)" \
        50  "50 GiB" \
        80  "80 GiB" \
        120 "120 GiB" \
        rest "Занять всё остальное" \
        custom "Ввести вручную"
  )"
  rc=$?
  ui_clear
  case "$rc" in
    0) : ;;
    2) return 2 ;;
    1|255) return 1 ;;
    *) return 1 ;;
  esac

  if [[ "$root_gib" == "custom" ]]; then
    root_gib="$(
      ui_dialog dialog --clear --stdout \
        --title "root" \
        --ok-label "Готово" \
        --cancel-label "Отмена" \
        --help-button --help-label "Назад" \
        --inputbox "Введите размер root в GiB (например 30):" 10 74 "30"
    )"
    rc=$?
    ui_clear
    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac
  fi

  # rest = 0 (как маркер “занять остаток”)
  if [[ "$root_gib" == "rest" ]]; then
    root_gib="0"
  fi

  if ! [[ "$root_gib" =~ ^[0-9]+$ ]] || (( root_gib < 0 || root_gib > 8192 )); then
    ui_msg "Некорректный размер root: $root_gib\n\nДопустимо: 0..8192 GiB (0 = занять остаток)."
    return 2
  fi

  # Записываем наружу
  printf -v "$out_boot" "%s" "$boot_mib"
  printf -v "$out_swap" "%s" "$swap_gib"
  printf -v "$out_root" "%s" "$root_gib"

  return 0
}
