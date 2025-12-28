#!/usr/bin/env bash
set -Eeuo pipefail

dump_collect() {
  mkdir -p "$DUMP_DIR" || true

  {
    echo "=== STAGE ==="
    echo "${STAGE}"
    echo
    echo "=== DATE ==="
    date
    echo
    echo "=== KERNEL ==="
    uname -a
    echo
    echo "=== ROOT SOURCE ==="
    findmnt -n -o SOURCE / || true
    echo
    echo "=== FINDMNT ==="
    findmnt -rn || true
    echo
    echo "=== LSBLK ==="
    lsblk -a || true
    echo
    echo "=== BLKID ==="
    blkid || true
    echo
    echo "=== SWAPON ==="
    swapon --show || true
    echo
    echo "=== IP ROUTE ==="
    ip route || true
  } > "$DUMP_DIR/summary.txt" 2>&1 || true

  if [[ -n "${DISK:-}" && -b "${DISK:-}" ]]; then
    {
      echo "=== DISK: $DISK ==="
      parted "$DISK" -s print || true
      echo
      sgdisk -p "$DISK" || true
    } > "$DUMP_DIR/disk.txt" 2>&1 || true
  fi

  cp -f "$LOG_FILE" "$DUMP_DIR/ovh_pve_reinstall.log" 2>/dev/null || true
  tar -czf "$DUMP_TGZ" -C "$(dirname "$DUMP_DIR")" "$(basename "$DUMP_DIR")" 2>/dev/null || true
}
