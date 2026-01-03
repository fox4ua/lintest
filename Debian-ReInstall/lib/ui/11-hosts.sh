#!/usr/bin/env bash

# ui_pick_hosts OUT_DOMAIN OUT_FQDN HOSTNAME_SHORT
# return: 0=ok, 1=cancel/esc, 2=back
ui_pick_hosts() {
  local out_domain="$1"
  local out_fqdn="$2"
  local hn_short="$3"

  local rc domain fqdn

  domain="${HOSTS_DOMAIN:-}"
  fqdn="${HOSTS_FQDN:-}"

  # domain (optional)
  domain="$(
    ui_dialog dialog --clear --stdout \
      --title "/etc/hosts" \
      --ok-label "Далее" \
      --cancel-label "Отмена" \
      --help-button --help-label "Назад" \
      --inputbox "Введите домен (опционально).\n\nМожно оставить пустым.\nПример: example.com" 12 74 "$domain"
  )"
  rc=$?
  ui_clear

  case "$rc" in
    0) : ;;
    2) return 2 ;;
    1|255) return 1 ;;
    *) return 1 ;;
  esac

  domain="$(echo "$domain" | awk '{$1=$1;print}')"

  # domain can be empty; validate only if non-empty
  if [[ -n "$domain" ]]; then
    if ! [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]]; then
      ui_msg "Некорректный домен: $domain"
      return 2
    fi
  fi

  # fqdn (optional) — НИКАКИХ вычислений/автосборок
  fqdn="$(
    ui_dialog dialog --clear --stdout \
      --title "/etc/hosts" \
      --ok-label "Готово" \
      --cancel-label "Отмена" \
      --help-button --help-label "Назад" \
      --inputbox "Введите FQDN (опционально).\n\nМожно оставить пустым — тогда будет использован только hostname.\nПример: ${hn_short}.example.com" 12 74 "$fqdn"
  )"
  rc=$?
  ui_clear

  case "$rc" in
    0) : ;;
    2) return 2 ;;
    1|255) return 1 ;;
    *) return 1 ;;
  esac

  fqdn="$(echo "$fqdn" | awk '{$1=$1;print}')"

  # fqdn can be empty; validate only if non-empty
  if [[ -n "$fqdn" ]]; then
    if ! [[ "$fqdn" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; then
      ui_msg "Некорректный FQDN: $fqdn"
      return 2
    fi
  fi

  printf -v "$out_domain" "%s" "$domain"
  printf -v "$out_fqdn" "%s" "$fqdn"
  return 0
}
