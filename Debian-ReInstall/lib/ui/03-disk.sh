#!/usr/bin/env bash

# ui_pick_disk OUT_DISK
# return: 0=Apply, 1=Cancel/ESC, 2=Back
ui_pick_disk() {
  local out_disk="$1"

  local choice rc
  local -a items=()

  # собираем /dev/sdX, /dev/nvme0n1 и т.п.
  while IFS= read -r line; do
    # NAME TYPE SIZE MODEL
    # пример: sda disk 80G Samsung_SSD
    local name type size model
    name="$(awk '{print $1}' <<<"$line")"
    type="$(awk '{print $2}' <<<"$line")"
    size="$(awk '{print $3}' <<<"$line")"
    model="$(cut -d' ' -f4- <<<"$line")"

    [[ "$type" == "disk" ]] || continue

    local dev="/dev/$name"
    # небольшая защита: показываем только существующие block-девайсы
    [[ -b "$dev" ]] || continue

    [[ -n "$model" ]] || model="-"
    items+=("$dev" "${size}  ${model}")
  done < <(lsblk -dn -o NAME,TYPE,SIZE,MODEL 2>/dev/null | sed 's/[[:space:]]\+/ /g')

  if [[ ${#items[@]} -eq 0 ]]; then
    ui_msg "Не найдено доступных дисков (lsblk вернул пусто)."
    return 1
  fi

  choice="$(
    ui_dialog dialog --clear --stdout \
      --title "Выбор диска" \
      --ok-label "Выбрать" \
      --cancel-label "Отмена" \
      --help-button \
      --help-label "Назад" \
      --menu "Выберите диск для установки (ВСЕ ДАННЫЕ БУДУТ УДАЛЕНЫ):" 18 74 10 \
      "${items[@]}"
  )"
  rc=$?
  ui_clear

  case "$rc" in
    0)
      [[ -b "$choice" ]] || return 1
      printf -v "$out_disk" "%s" "$choice"
      return 0
      ;;
    2) return 2 ;;         # Back
    1|255) return 1 ;;     # Cancel/ESC
    *) return 1 ;;
  esac
}
