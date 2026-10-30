#!/usr/bin/env bash

configure_hostname() (
    local required_command current_hostname new_hostname temporary_file
    local LC_ALL=C

    if ! command -v hostnamectl >/dev/null 2>&1; then
        printf 'Ошибка: для настройки имени сервера нужна команда hostnamectl.\n' >&2
        return 1
    fi
    if ! current_hostname=$(hostnamectl --static); then
        printf 'Ошибка: не удалось получить текущее имя сервера.\n' >&2
        return 1
    fi
    printf 'Текущее имя сервера: %s\n' "$current_hostname"

    while true; do
        if ! read -r -p 'Новое имя сервера (Enter — оставить текущее): ' new_hostname </dev/tty; then
            printf 'Ошибка: не удалось прочитать имя сервера из терминала.\n' >&2
            return 1
        fi
        if [[ -z "$new_hostname" || "$new_hostname" == "$current_hostname" ]]; then
            printf 'Смена имени сервера пропущена.\n'
            return 0
        fi
        if [[ "$new_hostname" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
            break
        fi
        printf 'Используйте от 1 до 63 строчных латинских букв, цифр или дефисов; дефис не допускается по краям.\n' >&2
    done

    for required_command in awk mktemp cp mv rm; do
        if ! command -v "$required_command" >/dev/null 2>&1; then
            printf 'Ошибка: для настройки имени сервера нужна команда %s.\n' "$required_command" >&2
            return 1
        fi
    done

    if ! temporary_file=$(mktemp /etc/.ocl-hosts.XXXXXX); then
        printf 'Ошибка: не удалось создать временный файл для /etc/hosts.\n' >&2
        return 1
    fi
    trap 'rm -f -- "$temporary_file"' EXIT

    # Готовим новый hosts заранее, сохраняя владельца и права исходного файла.
    if ! cp -p -- /etc/hosts "$temporary_file"; then
        printf 'Ошибка: не удалось скопировать /etc/hosts.\n' >&2
        return 1
    fi
    if ! awk -v new_hostname="$new_hostname" '
        $1 == "127.0.1.1" {
            found = 1
            entry = $0
            comment = ""
            comment_position = index(entry, "#")
            if (comment_position) {
                comment = substr(entry, comment_position)
                entry = substr(entry, 1, comment_position - 1)
            }
            match(entry, /^[[:space:]]*127[.]0[.]1[.]1/)
            address = substr(entry, 1, RLENGTH)
            names = substr(entry, RLENGTH + 1)
            if (names ~ /^[[:space:]]*$/) {
                entry = address "\t" new_hostname names
            } else {
                sub(/[^[:space:]]+/, new_hostname, names)
                entry = address names
            }
            print entry comment
            next
        }
        { print }
        END {
            if (!found) print "127.0.1.1\t" new_hostname
        }
    ' /etc/hosts >"$temporary_file"; then
        printf 'Ошибка: не удалось подготовить новое содержимое /etc/hosts.\n' >&2
        return 1
    fi

    if ! hostnamectl set-hostname "$new_hostname"; then
        printf 'Ошибка: не удалось изменить имя сервера на %s.\n' "$new_hostname" >&2
        return 1
    fi

    # Замена в пределах /etc атомарна; при её сбое возвращаем прежнее имя.
    if ! mv -f -- "$temporary_file" /etc/hosts; then
        printf 'Ошибка: не удалось обновить /etc/hosts.\n' >&2
        if ! hostnamectl set-hostname "$current_hostname"; then
            printf 'Ошибка: не удалось восстановить прежнее имя сервера %s. Требуется ручная проверка hostname и /etc/hosts.\n' "$current_hostname" >&2
        fi
        return 1
    fi

    printf 'Имя сервера изменено на %s.\n' "$new_hostname"
)
