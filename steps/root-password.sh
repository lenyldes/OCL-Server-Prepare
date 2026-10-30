#!/usr/bin/env bash

change_root_password() {
    local answer required_command root_password

    while [[ ${auto_mode:-false} != true ]]; do
        if ! read -r -p 'Сменить пароль root? [y/N] ' answer </dev/tty; then
            printf 'Ошибка: не удалось прочитать ответ из терминала.\n' >&2
            return 1
        fi

        case "$answer" in
            y|Y) break ;;
            n|N|'')
                printf 'Смена пароля root пропущена.\n'
                return 0
                ;;
            *) printf 'Введите y для смены пароля или n для пропуска.\n' >&2 ;;
        esac
    done

    for required_command in openssl chpasswd; do
        if ! command -v "$required_command" >/dev/null 2>&1; then
            printf 'Ошибка: для смены пароля нужна команда %s.\n' "$required_command" >&2
            return 1
        fi
    done

    if ! root_password=$(openssl rand -base64 24); then
        printf 'Ошибка: не удалось сгенерировать пароль root.\n' >&2
        return 1
    fi
    root_password=${root_password:0:30}

    if ! printf 'root:%s\n' "$root_password" | chpasswd; then
        unset root_password
        printf 'Ошибка: не удалось сменить пароль root.\n' >&2
        return 1
    fi

    ocl_saved_root_password=$root_password
    printf 'Пароль root успешно изменён.\n'
    unset root_password
}
