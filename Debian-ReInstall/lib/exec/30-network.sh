#!/usr/bin/env bash

net_try_ping() {
  local target="${1:-}"
  local tries="${2:-3}"
  local to="${3:-2}"

  require_cmd ping || return 2

  local i
  for ((i=1; i<=tries; i++)); do
    if ping -c1 -W"$to" "$target" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

net_try_tcp() {
  local host="${1:-}"
  local port="${2:-}"
  local to="${3:-3}"

  timeout "$to" bash -c "cat </dev/null >/dev/tcp/$host/$port" >/dev/null 2>&1
}

exec_net_check_host() {
  stage "net_check_host"

  local ip_test="1.1.1.1"
  local host_test="deb.debian.org"

  log "[=] host connectivity check: $ip_test / $host_test"

  local ip_ok=0
  if net_try_ping "$ip_test" 3 2; then
    ip_ok=1
    log "[+] ping $ip_test OK"
  else
    log "[!] ping $ip_test failed; trying TCP $ip_test:53"
    if net_try_tcp "$ip_test" 53 3; then
      ip_ok=1
      log "[+] TCP $ip_test:53 OK (ICMP may be blocked)"
    fi
  fi

  if [[ "$ip_ok" != "1" ]]; then
    log "[!] No external connectivity."
    require_cmd ip && run ip -br addr || true
    require_cmd ip && run ip route || true
    run cat /etc/resolv.conf || true
    fatal "No internet connectivity: cannot reach $ip_test (ping and TCP:53 failed)."
  fi

  if getent hosts "$host_test" >/dev/null 2>&1; then
    log "[+] DNS resolve $host_test OK"
  else
    log "[!] DNS resolve $host_test FAILED"
    run cat /etc/resolv.conf || true
    fatal "DNS is not working on host: cannot resolve $host_test (check /etc/resolv.conf)."
  fi

  if net_try_ping "$host_test" 2 2; then
    log "[+] ping $host_test OK"
  else
    log "[!] ping $host_test failed (ICMP may be blocked). DNS works, continuing."
  fi
}

prepare_target_resolv_conf() {
  mkdir -p "$TARGET_DIR/etc"
  if [[ -L "$TARGET_DIR/etc/resolv.conf" ]]; then
    rm -f "$TARGET_DIR/etc/resolv.conf"
  fi
}

host_resolv_conf_source() {
  local -a candidates=()

  if [[ -e /etc/resolv.conf ]]; then
    if grep -qE '^\s*nameserver\s+127\.0\.0\.53(\s|$)' /etc/resolv.conf; then
      candidates+=(/run/systemd/resolve/resolv.conf)
      candidates+=(/run/NetworkManager/resolv.conf)
      candidates+=(/run/resolvconf/resolv.conf)
    else
      candidates+=(/etc/resolv.conf)
      candidates+=(/run/systemd/resolve/resolv.conf)
      candidates+=(/run/NetworkManager/resolv.conf)
      candidates+=(/run/resolvconf/resolv.conf)
    fi
  else
    candidates+=(/run/systemd/resolve/resolv.conf)
    candidates+=(/run/NetworkManager/resolv.conf)
    candidates+=(/run/resolvconf/resolv.conf)
  fi

  local src
  for src in "${candidates[@]}"; do
    if [[ -e "$src" ]] && grep -qE '^\s*nameserver\s+' "$src"; then
      echo "$src"
      return 0
    fi
  done
  return 1
}

get_host_nameservers() {
  local src=""

  if src="$(host_resolv_conf_source)"; then
    :
  else
    src=""
  fi

  if [[ -n "$src" ]]; then
    awk '/^nameserver[[:space:]]+/{print $2}' "$src" 2>/dev/null | awk '$1!="127.0.0.53"'
  fi
}

get_fallback_dns_list() {
  local -a dns_list=()
  local -a host_dns=()

  if [[ -n "${NET_FALLBACK_DNS:-}" ]]; then
    local ns
    for ns in $NET_FALLBACK_DNS; do
      dns_list+=("$ns")
    done
  else
    while IFS= read -r ns; do
      host_dns+=("$ns")
    done < <(get_host_nameservers)

    dns_list+=("${host_dns[@]}")
    dns_list+=("1.1.1.1" "8.8.8.8")
    if [[ "${NET6_ENABLE:-0}" == "1" ]]; then
      dns_list+=("2606:4700:4700::1111" "2001:4860:4860::8888")
    fi
  fi

  printf '%s\n' "${dns_list[@]}" | awk '!seen[$0]++'
}

write_resolv_conf_defaults() {
  prepare_target_resolv_conf
  {
    echo "options timeout:1 attempts:2 rotate"
    local ns
    while IFS= read -r ns; do
      [[ -n "$ns" ]] && echo "nameserver $ns"
    done < <(get_fallback_dns_list)
  } >"$TARGET_DIR/etc/resolv.conf"
}

write_target_resolv_conf_from_host() {
  local src="/etc/resolv.conf"
  [[ -f /run/systemd/resolve/resolv.conf ]] && src="/run/systemd/resolve/resolv.conf"
  [[ -f /run/NetworkManager/resolv.conf ]] && src="/run/NetworkManager/resolv.conf"

  rm -f "$TARGET_DIR/etc/resolv.conf"
  install -m 0644 "$src" "$TARGET_DIR/etc/resolv.conf"
}

write_resolv_conf_fallback() {
  prepare_target_resolv_conf
  local dns=""
  if [[ "${NET4_ENABLE:-1}" == "1" && -n "${NET4_DNS:-}" ]]; then
    dns+=" ${NET4_DNS}"
  fi
  if [[ "${NET6_ENABLE:-0}" == "1" && -n "${NET6_DNS:-}" ]]; then
    dns+=" ${NET6_DNS}"
  fi
  dns="${dns# }"

  if [[ -z "$dns" ]]; then
    return 0
  fi

  {
    local ns
    for ns in $dns; do
      echo "nameserver $ns"
    done
  } >"$TARGET_DIR/etc/resolv.conf"
}

write_host_resolv_conf() {
  prepare_target_resolv_conf
  local src=""
  local dns=""
  local -a dns_list=()

  if src="$(host_resolv_conf_source)"; then
    :
  else
    src=""
  fi

  if [[ -n "$src" ]]; then
    cp -f "$src" "$TARGET_DIR/etc/resolv.conf"
    return 0
  fi

  if [[ -n "${NET_IFACE:-}" ]]; then
    dns="$(net_current_get_dns "$NET_IFACE" || true)"
  fi

  if [[ -n "$dns" ]]; then
    local ns
    for ns in $dns; do
      [[ "$ns" == "127.0.0.53" ]] && continue
      dns_list+=("$ns")
    done
  fi

  if [[ ${#dns_list[@]} -eq 0 ]]; then
    while IFS= read -r ns; do
      dns_list+=("$ns")
    done < <(get_fallback_dns_list)
  fi

  {
    local ns
    for ns in "${dns_list[@]}"; do
      echo "nameserver $ns"
    done
  } >"$TARGET_DIR/etc/resolv.conf"
}

ensure_target_nsswitch_dns() {
  local f="$TARGET_DIR/etc/nsswitch.conf"
  if [[ ! -f "$f" ]]; then
    cat >"$f" <<'EOF'
passwd:         files
group:          files
shadow:         files

hosts:          files dns
networks:       files

protocols:      db files
services:       db files
ethers:         db files
rpc:            db files
EOF
    return 0
  fi
  if ! grep -qE '^hosts:.*\sdns(\s|$)' "$f"; then
    sed -i 's/^hosts:.*/hosts:          files dns/' "$f"
  fi
}

exec_net_check_target() {
  local prev_stage="${STAGE:-}"

  stage "net_check_target"
  log "[=] target(chroot) DNS/connectivity check"

  write_target_resolv_conf_from_host
  ensure_target_nsswitch_dns

  if ! chroot_run_quiet "getent hosts deb.debian.org >/dev/null"; then
    log "[!] chroot DNS failed for deb.debian.org; fallback resolv.conf"
    write_resolv_conf_defaults
    chroot_run_quiet "getent hosts deb.debian.org >/dev/null" || fatal "DNS in chroot broken (deb.debian.org)"
  fi

  if ! chroot_run_quiet "getent hosts security.debian.org >/dev/null"; then
    log "[!] chroot DNS failed for security.debian.org; fallback resolv.conf"
    write_resolv_conf_defaults
    chroot_run_quiet "getent hosts security.debian.org >/dev/null" || fatal "DNS in chroot broken (security.debian.org)"
  fi

  chroot_run_quiet "ping -c1 -W2 1.1.1.1 >/dev/null" && log "[+] chroot ping 1.1.1.1 OK" || true

  STAGE="$prev_stage"
}

log_target_resolv_conf() {
  if [[ -f "$TARGET_DIR/etc/resolv.conf" ]]; then
    sed 's/^/[debug] /' "$TARGET_DIR/etc/resolv.conf" >>"$LOG_FILE"
  else
    log "[debug] $TARGET_DIR/etc/resolv.conf is missing"
  fi
}
