#!/usr/bin/env bash
set -Eeuo pipefail

UI_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/ui"

# shellcheck disable=SC1090
source "${UI_DIR}/00-common.sh"

# One file = one window
source "${UI_DIR}/01-welcome.sh"
source "${UI_DIR}/boot_mode.sh"
source "${UI_DIR}/disk.sh"
source "${UI_DIR}/swap.sh"
source "${UI_DIR}/boot.sh"
source "${UI_DIR}/lvm_mode.sh"
source "${UI_DIR}/root_size.sh"
source "${UI_DIR}/debian.sh"
source "${UI_DIR}/mirror.sh"
source "${UI_DIR}/hostname.sh"
source "${UI_DIR}/iface.sh"
source "${UI_DIR}/net_backend.sh"
source "${UI_DIR}/net_mode.sh"
source "${UI_DIR}/static_profile.sh"
source "${UI_DIR}/static_input.sh"
source "${UI_DIR}/root_password.sh"
source "${UI_DIR}/confirm.sh"
source "${UI_DIR}/done.sh"
