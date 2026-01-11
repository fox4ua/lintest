#!/usr/bin/env bash

: "${EXEC_DIR:?}"

# Common helpers
source "$EXEC_DIR/00-common.sh"

# Disk release / partitioning
source "$EXEC_DIR/10-disk.sh"

# FS/LVM and mounts
source "$EXEC_DIR/20-storage.sh"

# debootstrap + base config
source "$EXEC_DIR/30-system.sh"

# GRUB install
source "$EXEC_DIR/40-bootloader.sh"

# Cleanup (umount, vgchange -an)
source "$EXEC_DIR/90-cleanup.sh"

# Orchestrator
source "$EXEC_DIR/99-execute.sh"
