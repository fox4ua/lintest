#!/usr/bin/env bash

: "${EXEC_DIR:?}"

source "$EXEC_DIR/00-core.sh"
source "$EXEC_DIR/05-preflight.sh"
source "$EXEC_DIR/10-deps.sh"
source "$EXEC_DIR/20-chroot.sh"
source "$EXEC_DIR/30-network.sh"
source "$EXEC_DIR/40-disk.sh"
source "$EXEC_DIR/50-storage.sh"
source "$EXEC_DIR/60-debootstrap.sh"
source "$EXEC_DIR/70-packages.sh"
source "$EXEC_DIR/80-config.sh"
source "$EXEC_DIR/90-bootloader.sh"
source "$EXEC_DIR/95-cleanup.sh"
source "$EXEC_DIR/99-execute.sh"
