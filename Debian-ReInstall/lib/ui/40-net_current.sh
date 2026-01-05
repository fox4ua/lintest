#!/usr/bin/env bash

# ui_show_net_current [NET_STACK]
# Shows current network configuration (all interfaces) in the current environment.
# return: 0=continue, 1=cancel/esc, 2=back
ui_show_net_current() {
  local net_stack="${1:-}"
  local rc tmp

  tmp="$(mktemp -t net-current.XXXXXX)"
  {
    echo "CURRENT NETWORK CONFIGURATION (rescue environment)"
    if [[ -n "$net_stack" ]]; then
      echo "Selected stack: $net_stack"
      echo
    fi

    echo "=== Links (brief) ==="
    if command -v ip >/dev/null 2>&1; then
      ip -br link 2>/dev/null || true
    else
      echo "ip command not found"
    fi
    echo

    echo "=== Addresses (brief) ==="
    if command -v ip >/dev/null 2>&1; then
      ip -br addr 2>/dev/null || true
    fi
    echo

    echo "=== IPv4 routes ==="
    if command -v ip >/dev/null 2>&1; then
      ip -4 route show 2>/dev/null || true
    fi
    echo

    echo "=== IPv6 routes ==="
    if command -v ip >/dev/null 2>&1; then
      ip -6 route show 2>/dev/null || true
    fi
    echo

    echo "=== DNS ==="
    if command -v resolvectl >/dev/null 2>&1; then
      resolvectl status 2>/dev/null || true
    elif [[ -f /etc/resolv.conf ]]; then
      cat /etc/resolv.conf 2>/dev/null || true
    else
      echo "(no /etc/resolv.conf)"
    fi
    echo

    echo "Tip: this is the CURRENT (rescue) config, not what will be applied after install."
  } >"$tmp"

  ui_dialog dialog --clear \
    --title "Current network config" \
    --exit-label "Continue" \
    --extra-button --extra-label "Cancel" \
    --help-button --help-label "Back" \
    --textbox "$tmp" 22 78
  rc=$?
  ui_clear
  rm -f "$tmp" 2>/dev/null || true

  case "$rc" in
    0) return 0 ;;
    2) return 2 ;;
    3) return 1 ;;     # extra = Cancel
    1|255) return 1 ;;
    *) return 1 ;;
  esac
}
