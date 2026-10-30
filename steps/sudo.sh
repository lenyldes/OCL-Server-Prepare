#!/usr/bin/env bash

grant_sudo_access() {
    if ! command -v usermod >/dev/null 2>&1; then
        printf 'Ошибка: для выдачи прав sudo нужна команда usermod.\n' >&2
        return 1
    fi

    if ! usermod -aG sudo "$target_user"; then
        printf 'Ошибка: не удалось добавить пользователя %s в группу sudo.\n' "$target_user" >&2
        return 1
    fi

    printf 'Пользователь %s входит в группу sudo. Для применения прав войдите в систему заново.\n' "$target_user"
}
