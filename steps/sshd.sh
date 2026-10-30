#!/usr/bin/env bash

configure_sshd() (
    local template_file=${1:-} required_command ssh_port socket_listeners
    local config_file=/etc/ssh/sshd_config temporary_file='' restore_file='' backup_file=''
    local socket_activation=false config_installed=false
    local LC_ALL=C

    for required_command in sshd systemctl mktemp awk cp cmp chown chmod mv rm; do
        if ! command -v "$required_command" >/dev/null 2>&1; then
            printf 'Ошибка: для настройки SSH-сервера нужна команда %s.\n' "$required_command" >&2
            return 1
        fi
    done
    if [[ -z "$template_file" || ! -f "$template_file" || ! -r "$template_file" ]]; then
        printf 'Ошибка: шаблон настройки SSH-сервера недоступен.\n' >&2
        return 1
    fi
    if [[ ! -f "$config_file" || -L "$config_file" ]]; then
        printf 'Ошибка: /etc/ssh/sshd_config должен быть обычным файлом без символической ссылки.\n' >&2
        return 1
    fi

    while true; do
        if ! IFS= read -r -p 'Порт SSH (Enter — 18233): ' ssh_port </dev/tty; then
            printf 'Ошибка: не удалось прочитать порт SSH из терминала.\n' >&2
            return 1
        fi
        ssh_port=${ssh_port:-18233}
        if [[ "$ssh_port" =~ ^[0-9]+$ ]]; then
            # Удаляем начальные нули до арифметики, исключая восьмеричную запись и переполнение.
            ssh_port=${ssh_port#"${ssh_port%%[!0]*}"}
            if [[ -n "$ssh_port" && ${#ssh_port} -le 5 ]] && (( 10#$ssh_port <= 65535 )); then
                break
            fi
        fi
        printf 'Введите целое число от 1 до 65535.\n' >&2
    done

    restart_sshd() {
        if [[ "$socket_activation" == true ]]; then
            # Генератор Ubuntu перечитывает Port при daemon-reload; служба получает новые сокеты.
            systemctl daemon-reload &&
                systemctl restart ssh.socket ssh.service &&
                systemctl is-active --quiet ssh.socket &&
                systemctl is-active --quiet ssh.service
        else
            systemctl restart ssh.service && systemctl is-active --quiet ssh.service
        fi
    }

    cleanup_sshd() {
        local result=$?
        if [[ "$config_installed" == true ]]; then
            printf 'Ошибка применения SSH; восстанавливаем прежнюю конфигурацию.\n' >&2
            if restore_file=$(mktemp /etc/ssh/.ocl-sshd-restore.XXXXXX) &&
                cp -p -- "$backup_file" "$restore_file" &&
                mv -f -- "$restore_file" "$config_file" &&
                sshd -t && restart_sshd; then
                printf 'Прежняя конфигурация SSH восстановлена.\n' >&2
            else
                printf 'Ошибка отката SSH. Восстановите %s из %s и перезапустите SSH вручную.\n' \
                    "$config_file" "$backup_file" >&2
            fi
            result=1
        fi
        [[ -z "$temporary_file" ]] || rm -f -- "$temporary_file"
        [[ -z "$restore_file" ]] || rm -f -- "$restore_file"
        exit "$result"
    }
    trap cleanup_sshd EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    if ! temporary_file=$(mktemp /etc/ssh/.ocl-sshd.XXXXXX); then
        printf 'Ошибка: не удалось создать временный файл настройки SSH.\n' >&2
        return 1
    fi
    if ! awk -v port="$ssh_port" '
        /^[[:space:]]*Port[[:space:]]/ { print "Port " port; count++; next }
        { print }
        END { if (count != 1) exit 1 }
    ' "$template_file" >"$temporary_file" ||
        ! chown root:root "$temporary_file" || ! chmod 0644 "$temporary_file"; then
        printf 'Ошибка: не удалось подготовить конфигурацию SSH с единственным портом.\n' >&2
        return 1
    fi
    if ! sshd -t -f "$temporary_file"; then
        printf 'Ошибка: новая конфигурация SSH не прошла проверку sshd -t; настройки сохранены.\n' >&2
        return 1
    fi
    if cmp -s -- "$temporary_file" "$config_file"; then
        printf 'Такая конфигурация SSH уже записана; резервная копия и перезапуск не требуются.\n'
        return 0
    fi

    if systemctl is-active --quiet ssh.socket || systemctl is-enabled --quiet ssh.socket; then
        socket_activation=true
    fi
    if ! backup_file=$(mktemp /etc/ssh/sshd_config.ocl-backup.XXXXXX) ||
        ! cp -p -- "$config_file" "$backup_file"; then
        [[ -z "$backup_file" ]] || rm -f -- "$backup_file"
        printf 'Ошибка: не удалось сохранить резервную копию sshd_config; настройки сохранены.\n' >&2
        return 1
    fi
    printf 'Резервная копия SSH: %s\n' "$backup_file"
    # Кандидат и основной файл находятся в одном каталоге; замена атомарна.
    if ! mv -f -- "$temporary_file" "$config_file"; then
        printf 'Ошибка: не удалось установить новую конфигурацию SSH.\n' >&2
        return 1
    fi
    config_installed=true
    if ! restart_sshd; then
        printf 'Ошибка: не удалось перезапустить SSH с новой конфигурацией.\n' >&2
        return 1
    fi
    if [[ "$socket_activation" == true ]]; then
        if ! socket_listeners=$(systemctl show ssh.socket --property=Listen --value) ||
            ! awk -v port="$ssh_port" '
                {
                    for (i = 1; i <= NF; i += 2) {
                        if ($(i + 1) != "(Stream)" || $i !~ (":" port "$")) exit 1
                        count++
                    }
                }
                END { if (!count) exit 1 }
            ' <<<"$socket_listeners"; then
            printf 'Ошибка: ssh.socket слушает другие адреса или порты; проверьте пользовательские переопределения systemd.\n' >&2
            return 1
        fi
    fi
    config_installed=false
    printf 'SSH настроен на порту %s: вход по ключам, вход root и пароли отключены.\n' "$ssh_port"
)
