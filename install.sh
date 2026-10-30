#!/usr/bin/env bash

set -euo pipefail

if (( EUID != 0 )); then
    printf 'Ошибка: запустите установщик от root. Для перехода выполните sudo -i.\n' >&2
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    printf 'Ошибка: не удалось определить ОС через /etc/os-release.\n' >&2
    exit 1
fi

. /etc/os-release

if [[ ${ID:-} != ubuntu || ${VERSION_ID:-} != 24.04 ]]; then
    printf 'Ошибка: поддерживается Ubuntu 24.04 LTS. Обнаружена: %s.\n' "${PRETTY_NAME:-неизвестная ОС}" >&2
    exit 1
fi

printf 'OCL Server Prepare — подготовка сервера\n'
printf 'Система: %s\n' "${PRETTY_NAME:-Ubuntu 24.04 LTS}"
printf 'Предварительная проверка пройдена: запуск от root, ОС поддерживается.\n'
