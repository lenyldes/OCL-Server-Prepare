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

auto_mode=false
while true; do
    if ! read -r -p 'Установить со значениями по умолчанию? [y/N] ' answer </dev/tty; then
        printf 'Ошибка: не удалось прочитать ответ из терминала.\n' >&2
        exit 1
    fi
    case "$answer" in
        y|Y) auto_mode=true; break ;;
        n|N|'') break ;;
        *) printf 'Введите y для установки по умолчанию или n для ручной настройки.\n' >&2 ;;
    esac
done
if [[ "$auto_mode" == true ]]; then
    export DEBIAN_FRONTEND=noninteractive
fi

ocl_saved_root_password=''
ocl_saved_user_password=''
ocl_existing_user=false
export -n ocl_saved_root_password ocl_saved_user_password

print_setup_summary() {
    local result=$?
    (( BASH_SUBSHELL == 0 )) || return "$result"

    printf '\nИтог настройки\n'
    if (( result == 0 )); then
        printf 'Настройка завершена успешно.\n'
    else
        printf 'Настройка остановлена с ошибкой (код %s).\n' "$result"
    fi
    if [[ -n "$ocl_saved_root_password" ]]; then
        printf 'Новый пароль root: %s\n' "$ocl_saved_root_password"
    fi
    if [[ -n "$ocl_saved_user_password" ]]; then
        printf 'Новый пароль пользователя %s: %s\n' "$target_user" "$ocl_saved_user_password"
    elif [[ "$ocl_existing_user" == true ]]; then
        printf 'Пароль пользователя %s сохранён; установщику неизвестен.\n' "$target_user"
    fi
    unset ocl_saved_root_password ocl_saved_user_password
    return "$result"
}
trap print_setup_summary EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

setup_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
. "$setup_dir/steps/root-password.sh"
. "$setup_dir/steps/user.sh"
. "$setup_dir/steps/sudo.sh"
. "$setup_dir/steps/sudo-nopasswd.sh"
. "$setup_dir/steps/hostname.sh"
. "$setup_dir/steps/ssh-keys.sh"
. "$setup_dir/steps/sshd.sh"
. "$setup_dir/steps/ufw.sh"
. "$setup_dir/steps/zsh.sh"

change_root_password
create_user
grant_sudo_access
configure_passwordless_sudo
configure_hostname
configure_ssh_keys "$setup_dir/keys/default.pub"
configure_sshd "$setup_dir/templates/sshd_config"
configure_ufw
configure_zsh "$setup_dir/templates"
