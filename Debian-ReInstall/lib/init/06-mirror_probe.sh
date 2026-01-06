#!/usr/bin/env bash
# shellcheck shell=bash

# Проверка, что зеркало содержит выбранный Debian suite.
# Используется в UI (выбор зеркала), чтобы не давать выбрать "мертвое" зеркало
# или зеркало без нужного релиза.
#
# Возврат:
#   0 = OK (suite найден)
#   1 = FAIL (suite не найден / зеркало недоступно)
#   2 = FAIL (нет curl/wget для проверки)
#
# Ошибка кладётся в глобальную переменную MIRROR_PROBE_ERR (для UI).

MIRROR_PROBE_ERR=""

_mirror_have() { command -v "$1" >/dev/null 2>&1; }

_mirror_probe_url() {
  # короткий GET (HEAD часто режут)
  local url="$1"

  if _mirror_have curl; then
    curl -fsSL -L --connect-timeout 4 --max-time 12 --range 0-1024 -o /dev/null "$url"
    return $?
  fi

  if _mirror_have wget; then
    # wget --spider это HEAD-подобное поведение, но обычно работает
    wget -q --spider --timeout=12 --tries=1 "$url"
    return $?
  fi

  return 2
}

mirror_probe_suite() {
  local mirror="${1%/}"
  local suite="${2:-}"
  local arch="${3:-}"

  MIRROR_PROBE_ERR=""

  if [[ -z "$mirror" || -z "$suite" ]]; then
    MIRROR_PROBE_ERR="mirror_probe_suite: mirror/suite is empty"
    return 1
  fi

  if [[ -z "$arch" ]]; then
    arch="$(dpkg --print-architecture 2>/dev/null || true)"
    [[ -n "$arch" ]] || arch="amd64"
  fi

  # 1) Проверяем метаданные релиза (самый правильный сигнал, что suite есть)
  local url
  for url in \
    "$mirror/dists/$suite/InRelease" \
    "$mirror/dists/$suite/Release"
  do
    _mirror_probe_url "$url"
    case "$?" in
      0) return 0 ;;
      2)
        MIRROR_PROBE_ERR="Не найден curl/wget для проверки зеркала."
        return 2
        ;;
    esac
  done

  # 2) Дополнительная проверка: пакеты main для текущей архитектуры
  # (иногда релиз есть, но зеркало/прокси режет InRelease/Release)
  for url in \
    "$mirror/dists/$suite/main/binary-$arch/Packages.gz" \
    "$mirror/dists/$suite/main/binary-$arch/Packages.xz"
  do
    _mirror_probe_url "$url"
    case "$?" in
      0) return 0 ;;
      2)
        MIRROR_PROBE_ERR="Не найден curl/wget для проверки зеркала."
        return 2
        ;;
    esac
  done

  MIRROR_PROBE_ERR="Зеркало недоступно или не содержит suite: $suite"
  return 1
}
