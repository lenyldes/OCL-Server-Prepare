#!/usr/bin/env bash

configure_ufw() {
    local required_command ssh_config ssh_port
    local LC_ALL=C

    for required_command in sshd awk; do
        if ! command -v "$required_command" >/dev/null 2>&1; then
            printf 'Ошибка: для настройки UFW нужна команда %s.\n' "$required_command" >&2
            return 1
        fi
    done
    if ! command -v ufw >/dev/null 2>&1; then
        if ! command -v apt-get >/dev/null 2>&1; then
            printf 'Ошибка: для установки UFW нужна команда apt-get.\n' >&2
            return 1
        fi
        if ! apt-get update; then
            printf 'Ошибка: не удалось обновить список пакетов для установки UFW.\n' >&2
            return 1
        fi
        if ! apt-get install -y ufw; then
            printf 'Ошибка: не удалось установить UFW.\n' >&2
            return 1
        fi
    fi

    if ! ssh_config=$(sshd -T); then
        printf 'Ошибка: не удалось прочитать действующую конфигурацию SSH через sshd -T.\n' >&2
        return 1
    fi
    if ! ssh_port=$(awk '
        $1 == "port" {
            if (NF != 2 || $2 !~ /^[0-9]+$/ || length($2) > 5 || $2 < 1 || $2 > 65535) exit 1
            port = $2
            count++
        }
        END {
            if (count != 1) exit 1
            print port
        }
    ' <<<"$ssh_config"); then
        printf 'Ошибка: конфигурация SSH должна содержать единственный порт от 1 до 65535.\n' >&2
        return 1
    fi

    # UFW сам пропускает уже существующее одинаковое правило при повторном запуске.
    if ! ufw limit "$ssh_port/tcp" comment 'SSH limit'; then
        printf 'Ошибка: не удалось добавить правило UFW для SSH на порту %s.\n' "$ssh_port" >&2
        return 1
    fi
    if ! ufw default deny incoming; then
        printf 'Ошибка: не удалось запретить входящие соединения по умолчанию в UFW.\n' >&2
        return 1
    fi
    if ! ufw default allow outgoing; then
        printf 'Ошибка: не удалось разрешить исходящие соединения по умолчанию в UFW.\n' >&2
        return 1
    fi
    if ! ufw --force enable; then
        printf 'Ошибка: не удалось включить UFW.\n' >&2
        return 1
    fi

    printf 'UFW включён: SSH на порту %s защищён ограничением частоты подключений.\n' "$ssh_port"
}
