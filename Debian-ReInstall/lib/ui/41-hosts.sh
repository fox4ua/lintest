#!/usr/bin/env bash

# ui_pick_hosts OUT_DOMAIN OUT_FQDN HOSTNAME_SHORT
# return: 0=Continue, 1=Cancel/ESC (exit), 2=Back
ui_pick_hosts() {
  local out_domain="$1"
  local out_fqdn="$2"
  local hn_short="$3"

  local rc domain fqdn

  domain="${HOSTS_DOMAIN:-}"
  fqdn="${HOSTS_FQDN:-}"

  # domain (optional)
  while true; do
    domain="$(
      ui_dialog dialog --clear --stdout \
        --title "/etc/hosts" \
        --ok-label "Continue" \
        --cancel-label "Cancel" \
        --help-button --help-label "Back" \
        --inputbox "Enter domain (optional).\n\nMay be left blank.\nExample: example.com" 12 74 "$domain"
    )"
    rc=$?
    ui_clear

    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac

    domain="$(ui_trim "$domain")"

    # domain can be empty; validate only if non-empty
    if [[ -z "$domain" ]]; then
      break
    fi

    if ! [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]]; then
      ui_msg "Incorrect domain: $domain"
      continue
    fi

    break
  done

  # fqdn (optional) — НИКАКИХ вычислений/автосборок
  while true; do
    fqdn="$(
      ui_dialog dialog --clear --stdout \
        --title "/etc/hosts" \
        --ok-label "Continue" \
        --cancel-label "Cancel" \
        --help-button --help-label "Back" \
        --inputbox "Enter FQDN (optional).\n\nMay be left blank — then only hostname.\nExample: ${hn_short}.example.com" 12 74 "$fqdn"
    )"
    rc=$?
    ui_clear

    case "$rc" in
      0) : ;;
      2) return 2 ;;
      1|255) return 1 ;;
      *) return 1 ;;
    esac

    fqdn="$(ui_trim "$fqdn")"

    # fqdn can be empty; validate only if non-empty
    if [[ -z "$fqdn" ]]; then
      break
    fi

    if ! [[ "$fqdn" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; then
      ui_msg "Incorrect FQDN: $fqdn"
      continue
    fi

    break
  done

  printf -v "$out_domain" "%s" "$domain"
  printf -v "$out_fqdn" "%s" "$fqdn"
  return 0
}
