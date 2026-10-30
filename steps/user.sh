#!/usr/bin/env bash

create_user() {
    local required_command status_line status_user password_status status_details

    for required_command in adduser getent passwd; do
        if ! command -v "$required_command" >/dev/null 2>&1; then
            printf 'Ошибка: для создания пользователя нужна команда %s.\n' "$required_command" >&2
            return 1
        fi
    done

    # Выбранное имя используется последующими шагами настройки.
    while true; do
        if ! read -r -p 'Имя пользователя [lenyldes]: ' target_user </dev/tty; then
            printf 'Ошибка: не удалось прочитать имя пользователя из терминала.\n' >&2
            return 1
        fi
        target_user=${target_user:-lenyldes}

        if [[ ! "$target_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
            printf 'Используйте до 32 строчных латинских букв, цифр, _ или -; первый символ — буква или _.\n' >&2
        elif [[ "$target_user" == root ]]; then
            printf 'Для настройки нужен отдельный пользователь. Введите имя, отличное от root.\n' >&2
        else
            break
        fi
    done

    if getent passwd "$target_user" >/dev/null; then
        printf 'Пользователь %s уже существует. Его пароль сохраняется.\n' "$target_user"
    elif ! adduser --comment "" "$target_user" </dev/tty; then
        printf 'Ошибка: не удалось завершить создание пользователя %s.\n' "$target_user" >&2
        return 1
    fi

    if ! status_line=$(passwd -S "$target_user"); then
        printf 'Ошибка: не удалось проверить пароль пользователя %s.\n' "$target_user" >&2
        return 1
    fi
    read -r status_user password_status status_details <<<"$status_line"

    if [[ "$password_status" != P ]]; then
        printf 'Ошибка: пароль пользователя %s отсутствует или заблокирован. Выполните passwd %s и повторите запуск.\n' \
            "$target_user" "$target_user" >&2
        return 1
    fi

    printf 'Пользователь %s готов.\n' "$target_user"
}
