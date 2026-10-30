#!/usr/bin/env bash

configure_zsh() (
    local template_dir=${1:-} required_command account_record account_name
    local password_field user_id group_id user_description home_dir login_shell primary_group
    local package package_status zsh_binary omz_dir plugin work_dir='' prepared_file=''
    local -a missing_packages=()
    local LC_ALL=C

    if [[ -z ${target_user:-} || "$target_user" == root || -z "$template_dir" ]]; then
        printf 'Ошибка: для настройки Zsh нужны отдельный пользователь и каталог шаблонов.\n' >&2
        return 1
    fi
    for required_command in getent id runuser env dpkg-query curl mktemp cp cmp chmod chown mv rm chsh; do
        if ! command -v "$required_command" >/dev/null 2>&1; then
            printf 'Ошибка: для настройки Zsh нужна команда %s.\n' "$required_command" >&2
            return 1
        fi
    done
    if ! account_record=$(getent passwd "$target_user") ||
        ! primary_group=$(id -gn -- "$target_user"); then
        printf 'Ошибка: не удалось получить сведения о пользователе %s.\n' "$target_user" >&2
        return 1
    fi
    IFS=: read -r account_name password_field user_id group_id user_description home_dir login_shell <<<"$account_record"
    if [[ "$account_name" != "$target_user" || "$user_id" == 0 ||
        "$home_dir" != /* || "$home_dir" == / || ! -d "$home_dir" || -z "$primary_group" ]]; then
        printf 'Ошибка: домашний каталог или основная группа пользователя %s недоступны.\n' "$target_user" >&2
        return 1
    fi
    for required_command in zshrc lenyldes.zsh-theme; do
        if [[ ! -f "$template_dir/$required_command" || ! -r "$template_dir/$required_command" ]]; then
            printf 'Ошибка: недоступен шаблон %s.\n' "$template_dir/$required_command" >&2
            return 1
        fi
    done

    omz_dir="$home_dir/.oh-my-zsh"
    # Чистое окружение исключает наследование HOME/ZDOTDIR/ZSH от root.
    zsh_as_user() {
        runuser -u "$target_user" -g "$primary_group" -- env -i \
            HOME="$home_dir" USER="$target_user" LOGNAME="$target_user" \
            PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin TERM=dumb \
            sh -c 'cd -- "$HOME" && exec "$@"' sh "$@"
    }

    zsh_check_repository() {
        local directory=$1 repository=$2 marker=$3 repository_root remote_url
        if [[ -L "$directory" || ! -d "$directory/.git" || ! -f "$directory/$marker" ]] ||
            ! repository_root=$(zsh_as_user git -C "$directory" rev-parse --show-toplevel) ||
            [[ "$repository_root" != "$directory" ]] ||
            ! remote_url=$(zsh_as_user git -C "$directory" remote get-url origin) ||
            [[ "$remote_url" != "https://github.com/$repository" &&
                "$remote_url" != "https://github.com/$repository.git" ]]; then
            printf 'Ошибка: %s должен быть репозиторием https://github.com/%s с файлом %s. Данные сохранены.\n' \
                "$directory" "$repository" "$marker" >&2
            return 1
        fi
    }

    zsh_prepare_directory() {
        if [[ -L "$1" || ( -e "$1" && ! -d "$1" ) ]]; then
            printf 'Ошибка: %s должен быть обычным каталогом без символической ссылки.\n' "$1" >&2
            return 1
        fi
        if ! zsh_as_user mkdir -p -- "$1"; then
            printf 'Ошибка: не удалось подготовить каталог %s.\n' "$1" >&2
            return 1
        fi
    }

    zsh_check_setting() {
        if [[ -L "$1" || ( -e "$1" && ! -f "$1" ) ]]; then
            printf 'Ошибка: %s должен быть обычным файлом без символической ссылки.\n' "$1" >&2
            return 1
        fi
    }

    zsh_install_setting() {
        local source_file=$1 destination=$2 backup_file
        if ! zsh_check_setting "$destination"; then
            return 1
        fi
        if [[ -f "$destination" ]] && cmp -s -- "$source_file" "$destination"; then
            if ! chown "$target_user:$primary_group" "$destination" || ! chmod 0644 "$destination"; then
                printf 'Ошибка: не удалось настроить права файла %s.\n' "$destination" >&2
                return 1
            fi
            return 0
        fi
        if ! prepared_file=$(mktemp "${destination}.ocl-tmp.XXXXXX") ||
            ! cp -- "$source_file" "$prepared_file" ||
            ! chown "$target_user:$primary_group" "$prepared_file" || ! chmod 0644 "$prepared_file"; then
            printf 'Ошибка: не удалось подготовить файл %s.\n' "$destination" >&2
            return 1
        fi
        if [[ -f "$destination" ]]; then
            if ! backup_file=$(mktemp "${destination}.ocl-backup.XXXXXX") ||
                ! cp -p -- "$destination" "$backup_file" ||
                ! chown "$target_user:$primary_group" "$backup_file"; then
                printf 'Ошибка: не удалось сохранить резервную копию файла %s.\n' "$destination" >&2
                return 1
            fi
            printf 'Резервная копия настроек Zsh: %s\n' "$backup_file"
        fi
        if ! mv -f -- "$prepared_file" "$destination"; then
            printf 'Ошибка: не удалось применить файл %s.\n' "$destination" >&2
            return 1
        fi
        prepared_file=''
    }

    if ! zsh_check_setting "$home_dir/.zshrc"; then
        return 1
    fi
    if [[ -L "$omz_dir" || ( -e "$omz_dir" && ! -d "$omz_dir" ) ]]; then
        printf 'Ошибка: %s должен быть обычным каталогом Oh My Zsh. Данные сохранены.\n' "$omz_dir" >&2
        return 1
    fi
    for package in zsh git fzf; do
        if ! package_status=$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null) ||
            [[ "$package_status" != 'install ok installed' ]]; then
            missing_packages+=("$package")
        fi
    done
    if (( ${#missing_packages[@]} )); then
        if ! command -v apt-get >/dev/null 2>&1; then
            printf 'Ошибка: для установки пакетов Zsh нужна команда apt-get.\n' >&2
            return 1
        fi
        if ! apt-get update || ! apt-get install -y "${missing_packages[@]}"; then
            printf 'Ошибка: не удалось установить необходимые пакеты Zsh.\n' >&2
            return 1
        fi
    fi
    if ! zsh_binary=$(command -v zsh) || ! command -v git >/dev/null 2>&1 ||
        ! command -v fzf >/dev/null 2>&1; then
        printf 'Ошибка: после установки должны быть доступны zsh, git и fzf.\n' >&2
        return 1
    fi
    if ! "$zsh_binary" -n "$template_dir/zshrc" || ! "$zsh_binary" -n "$template_dir/lenyldes.zsh-theme"; then
        printf 'Ошибка: синтаксис шаблонов Zsh не прошёл проверку.\n' >&2
        return 1
    fi
    if ! work_dir=$(mktemp -d); then
        printf 'Ошибка: не удалось подготовить временный каталог для Zsh.\n' >&2
        return 1
    fi
    trap 'if [[ -n "$prepared_file" ]]; then rm -f -- "$prepared_file"; fi; rm -rf -- "$work_dir"' EXIT
    if ! chown "$target_user:$primary_group" "$work_dir"; then
        printf 'Ошибка: не удалось назначить владельца временного каталога Zsh.\n' >&2
        return 1
    fi

    if [[ ! -e "$omz_dir" ]]; then
        if ! curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh \
            -o "$work_dir/install.sh" || ! chmod 0644 "$work_dir/install.sh"; then
            printf 'Ошибка: не удалось загрузить установщик Oh My Zsh.\n' >&2
            return 1
        fi
        # Инсталлятор создаёт свой .zshrc только во временном ZDOTDIR.
        if ! zsh_as_user env ZSH="$omz_dir" ZDOTDIR="$work_dir" CHSH=no RUNZSH=no KEEP_ZSHRC=yes \
            sh "$work_dir/install.sh" --unattended --keep-zshrc; then
            printf 'Ошибка: не удалось установить Oh My Zsh для пользователя %s.\n' "$target_user" >&2
            return 1
        fi
    fi
    if ! zsh_check_repository "$omz_dir" ohmyzsh/ohmyzsh oh-my-zsh.sh ||
        ! zsh_prepare_directory "$omz_dir/custom" ||
        ! zsh_prepare_directory "$omz_dir/custom/plugins" ||
        ! zsh_prepare_directory "$omz_dir/custom/themes"; then
        return 1
    fi
    for plugin in zsh-completions zsh-autosuggestions zsh-syntax-highlighting; do
        if [[ ! -e "$omz_dir/custom/plugins/$plugin" && ! -L "$omz_dir/custom/plugins/$plugin" ]]; then
            if ! zsh_as_user git clone --depth=1 "https://github.com/zsh-users/$plugin.git" \
                "$omz_dir/custom/plugins/$plugin"; then
                printf 'Ошибка: не удалось установить плагин %s.\n' "$plugin" >&2
                return 1
            fi
        fi
        if ! zsh_check_repository "$omz_dir/custom/plugins/$plugin" "zsh-users/$plugin" "$plugin.plugin.zsh"; then
            return 1
        fi
    done
    for plugin in colored-man-pages docker docker-compose kubectl helm terraform fzf; do
        if [[ ! -f "$omz_dir/plugins/$plugin/$plugin.plugin.zsh" ]]; then
            printf 'Ошибка: в Oh My Zsh отсутствует встроенный плагин %s.\n' "$plugin" >&2
            return 1
        fi
    done
    if ! zsh_check_setting "$omz_dir/custom/themes/lenyldes.zsh-theme" ||
        ! zsh_install_setting "$template_dir/lenyldes.zsh-theme" "$omz_dir/custom/themes/lenyldes.zsh-theme" ||
        ! zsh_install_setting "$template_dir/zshrc" "$home_dir/.zshrc"; then
        return 1
    fi
    # Оболочка меняется только после успешной установки всех компонентов и настроек.
    if [[ "$login_shell" != "$zsh_binary" ]] && ! chsh -s "$zsh_binary" "$target_user"; then
        printf 'Ошибка: не удалось изменить оболочку пользователя %s на %s.\n' "$target_user" "$zsh_binary" >&2
        return 1
    fi
    printf 'Zsh и Oh My Zsh настроены для пользователя %s. Войдите заново для применения оболочки.\n' "$target_user"
)
