#!/usr/bin/env bash

configure_ssh_keys() (
    local default_key_file=${1:-} required_command account_record account_name
    local password_field user_id group_id user_description home_dir login_shell primary_group
    local ssh_dir authorized_keys work_dir candidate_file prepared_file installed_temporary=''
    local default_key default_type default_info default_fingerprint key_line key_type key_material
    local key_comment key_info key_bits fingerprint fingerprints='' first_key=true
    local LC_ALL=C

    if [[ -z ${target_user:-} || -z "$default_key_file" ]]; then
        printf 'Ошибка: для настройки SSH нужны имя пользователя и файл ключа по умолчанию.\n' >&2
        return 1
    fi
    for required_command in getent id ssh-keygen mktemp cp mkdir chown chmod mv rm awk tail; do
        if ! command -v "$required_command" >/dev/null 2>&1; then
            printf 'Ошибка: для настройки SSH нужна команда %s.\n' "$required_command" >&2
            return 1
        fi
    done

    if ! account_record=$(getent passwd "$target_user") ||
        ! primary_group=$(id -gn -- "$target_user"); then
        printf 'Ошибка: не удалось получить сведения о пользователе %s.\n' "$target_user" >&2
        return 1
    fi
    IFS=: read -r account_name password_field user_id group_id user_description home_dir login_shell <<<"$account_record"
    if [[ "$account_name" != "$target_user" || "$home_dir" != /* || ! -d "$home_dir" || -z "$primary_group" ]]; then
        printf 'Ошибка: домашний каталог или основная группа пользователя %s недоступны.\n' "$target_user" >&2
        return 1
    fi
    ssh_dir="$home_dir/.ssh"
    authorized_keys="$ssh_dir/authorized_keys"
    if [[ -L "$ssh_dir" || ( -e "$ssh_dir" && ! -d "$ssh_dir" ) ||
        -L "$authorized_keys" || ( -e "$authorized_keys" && ! -f "$authorized_keys" ) ]]; then
        printf 'Ошибка: .ssh и authorized_keys должны быть обычным каталогом и файлом без символических ссылок.\n' >&2
        return 1
    fi

    if ! work_dir=$(mktemp -d); then
        printf 'Ошибка: не удалось создать временный каталог для настройки SSH.\n' >&2
        return 1
    fi
    trap 'rm -rf -- "$work_dir"; if [[ -n "$installed_temporary" ]]; then rm -f -- "$installed_temporary"; fi' EXIT
    candidate_file="$work_dir/candidate.pub"
    prepared_file="$work_dir/authorized_keys"

    if ! IFS= read -r default_key <"$default_key_file" ||
        ! default_info=$(ssh-keygen -lf "$default_key_file" -E sha256 2>/dev/null); then
        printf 'Ошибка: не удалось прочитать действительный публичный ключ по умолчанию.\n' >&2
        return 1
    fi
    read -r default_type key_material key_comment <<<"$default_key"
    read -r key_bits default_fingerprint key_comment <<<"$default_info"
    printf 'Ключ SSH по умолчанию (%s): %s\n' "$default_type" "$default_fingerprint"

    if [[ -e "$authorized_keys" ]]; then
        if ! cp -- "$authorized_keys" "$prepared_file"; then
            printf 'Ошибка: не удалось прочитать существующий authorized_keys.\n' >&2
            return 1
        fi
        # ssh-keygen учитывает ключи с options; их ограничения сохраняются при повторном вводе.
        if ! key_info=$(ssh-keygen -lf "$prepared_file" -E sha256 2>/dev/null); then
            key_info=''
        fi
        if ! fingerprints=$(printf '%s\n' "$key_info" | awk 'NF { print $2 }'); then
            printf 'Ошибка: не удалось получить отпечатки существующих SSH-ключей.\n' >&2
            return 1
        fi
    elif ! : >"$prepared_file"; then
        printf 'Ошибка: не удалось подготовить файл authorized_keys.\n' >&2
        return 1
    fi

    while true; do
        if [[ "$first_key" == true ]]; then
            if ! IFS= read -r -p 'Публичный SSH-ключ (Enter — ключ по умолчанию): ' key_line </dev/tty; then
                printf 'Ошибка: не удалось прочитать SSH-ключ из терминала.\n' >&2
                return 1
            fi
            key_line=${key_line:-$default_key}
        else
            if ! IFS= read -r -p 'Дополнительный публичный SSH-ключ (Enter — завершить): ' key_line </dev/tty; then
                printf 'Ошибка: не удалось прочитать SSH-ключ из терминала.\n' >&2
                return 1
            fi
            [[ -n "$key_line" ]] || break
        fi

        read -r key_type key_material key_comment <<<"$key_line"
        case "$key_type" in
            ssh-*|ecdsa-*|sk-*) ;;
            *)
                printf 'Введите публичный OpenSSH-ключ целиком одной строкой, без options.\n' >&2
                continue
                ;;
        esac
        if ! printf '%s\n' "$key_line" >"$candidate_file"; then
            printf 'Ошибка: не удалось подготовить SSH-ключ для проверки.\n' >&2
            return 1
        fi
        if ! key_info=$(ssh-keygen -lf "$candidate_file" -E sha256 2>/dev/null); then
            printf 'Некорректный публичный SSH-ключ. Повторите ввод.\n' >&2
            continue
        fi
        read -r key_bits fingerprint key_comment <<<"$key_info"

        if [[ $'\n'"$fingerprints"$'\n' == *$'\n'"$fingerprint"$'\n'* ]]; then
            printf 'Этот SSH-ключ уже добавлен; существующая запись сохранена.\n'
        else
            # Дописываем ключ с новой строки, даже если исходный файл не завершался переводом строки.
            if [[ -s "$prepared_file" ]]; then
                if ! key_comment=$(tail -c 1 -- "$prepared_file"); then
                    printf 'Ошибка: не удалось прочитать подготовленный authorized_keys.\n' >&2
                    return 1
                fi
                if [[ -n "$key_comment" ]] && ! printf '\n' >>"$prepared_file"; then
                    printf 'Ошибка: не удалось дополнить authorized_keys.\n' >&2
                    return 1
                fi
            fi
            if ! printf '%s\n' "$key_line" >>"$prepared_file"; then
                printf 'Ошибка: не удалось добавить SSH-ключ.\n' >&2
                return 1
            fi
            fingerprints+=$'\n'"$fingerprint"
        fi
        first_key=false
    done

    if ! ssh-keygen -lf "$prepared_file" -E sha256 >/dev/null 2>&1; then
        printf 'Ошибка: в authorized_keys должен быть хотя бы один действительный SSH-ключ.\n' >&2
        return 1
    fi
    if ! mkdir -p -- "$ssh_dir" || ! chown "$target_user:$primary_group" "$ssh_dir" ||
        ! chmod 0700 "$ssh_dir"; then
        printf 'Ошибка: не удалось подготовить каталог .ssh пользователя %s.\n' "$target_user" >&2
        return 1
    fi
    if ! installed_temporary=$(mktemp "$ssh_dir/.ocl-authorized-keys.XXXXXX") ||
        ! cp -- "$prepared_file" "$installed_temporary" ||
        ! chown "$target_user:$primary_group" "$installed_temporary" ||
        ! chmod 0600 "$installed_temporary" ||
        ! mv -f -- "$installed_temporary" "$authorized_keys"; then
        printf 'Ошибка: не удалось установить authorized_keys пользователя %s.\n' "$target_user" >&2
        return 1
    fi

    printf 'SSH-ключи пользователя %s настроены.\n' "$target_user"
)
