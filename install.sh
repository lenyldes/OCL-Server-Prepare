#!/usr/bin/env bash

set -euo pipefail

for required_command in curl tar mktemp; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        printf 'Ошибка: для загрузки установщика нужна команда %s.\n' "$required_command" >&2
        exit 1
    fi
done

ocl_work_dir=$(mktemp -d)
trap 'rm -rf -- "$ocl_work_dir"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Загрузка OCL Server Prepare…\n'
if ! curl -fsSL https://github.com/lenyldes/OCL-Server-Prepare/archive/refs/heads/main.tar.gz \
    -o "$ocl_work_dir/project.tar.gz"; then
    printf 'Ошибка: не удалось загрузить архив проекта.\n' >&2
    exit 1
fi

mkdir "$ocl_work_dir/project"
if ! tar -xzf "$ocl_work_dir/project.tar.gz" -C "$ocl_work_dir/project" --strip-components=1; then
    printf 'Ошибка: не удалось распаковать архив проекта.\n' >&2
    exit 1
fi

if [[ ! -f "$ocl_work_dir/project/setup.sh" ]]; then
    printf 'Ошибка: в архиве проекта отсутствует setup.sh.\n' >&2
    exit 1
fi

bash "$ocl_work_dir/project/setup.sh"
