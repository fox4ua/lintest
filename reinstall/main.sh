#!/usr/bin/env bash
set -euo pipefail

source lib/00-env.sh
source lib/10-log.sh
source lib/20-utils.sh

source lib/core/10-defaults.sh
source lib/core/20-validate.sh
source lib/core/30-finalize.sh
source lib/core/90-run.sh

source lib/input/10-cli.sh
source lib/input/20-console.sh
source lib/input/30-dialog.sh

main() {
  defaults_init

  input_cli "$@"   # заполнили что смогли из флагов

  # выбор UI режима: none|console|dialog
  case "${UI_MODE:-dialog}" in
    none)    : ;; # ничего не спрашиваем, только флаги
    console) input_console_fill_missing ;;
    dialog)  input_dialog_fill_missing ;;
  esac

  validate_config
  finalize_config

  run_install
}
main "$@"
