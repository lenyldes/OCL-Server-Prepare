#!/usr/bin/env bash

configure_passwordless_sudo() (
    local required_command sudoers_file temporary_file installed_file

    for required_command in visudo mktemp cmp chown chmod ln rm; do
        if ! command -v "$required_command" >/dev/null 2>&1; then
            printf 'Ошибка: для настройки sudo без пароля нужна команда %s.\n' "$required_command" >&2
            return 1
        fi
    done

    sudoers_file="/etc/sudoers.d/$target_user"
    # Точка в имени исключает временный файл из правил, читаемых sudo.
    if ! temporary_file=$(mktemp /etc/sudoers.d/.ocl-nopasswd.XXXXXX); then
        printf 'Ошибка: не удалось создать временный файл настройки sudo.\n' >&2
        return 1
    fi
    trap 'rm -f -- "$temporary_file"' EXIT

    if ! printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$target_user" >"$temporary_file"; then
        printf 'Ошибка: не удалось записать правило sudo для пользователя %s.\n' "$target_user" >&2
        return 1
    fi

    installed_file=$temporary_file
    if [[ -e "$sudoers_file" || -L "$sudoers_file" ]]; then
        if [[ ! -f "$sudoers_file" || -L "$sudoers_file" ]] || ! cmp -s -- "$temporary_file" "$sudoers_file"; then
            printf 'Ошибка: файл %s уже существует и содержит другие настройки или не является обычным файлом.\n' "$sudoers_file" >&2
            return 1
        fi
        installed_file=$sudoers_file
    fi

    if ! visudo -cf "$temporary_file" >/dev/null; then
        printf 'Ошибка: правило sudo для пользователя %s не прошло проверку visudo.\n' "$target_user" >&2
        return 1
    fi

    if ! chown root:root "$installed_file" || ! chmod 0440 "$installed_file"; then
        printf 'Ошибка: не удалось задать владельца и права файла настройки sudo.\n' >&2
        return 1
    fi

    # Создаём целевой файл атомарно, без перезаписи существующих настроек.
    if [[ "$installed_file" == "$temporary_file" ]] && ! ln -- "$temporary_file" "$sudoers_file"; then
        printf 'Ошибка: не удалось установить файл %s.\n' "$sudoers_file" >&2
        return 1
    fi

    printf 'Для пользователя %s настроено sudo без пароля.\n' "$target_user"
)
