#!/bin/bash
# 列出隐藏备份（.名称*backup*、.名称*.pre-release-*，文件或目录）；加 -d 才删除。
# 不进入 .git、虚拟环境、缓存和非隐藏的 dist 子目录（如 dist/x86_64），dist 下隐藏的旧发布目录照常处理。
set -euo pipefail
cd "$(dirname "$0")"

find . \( -name .git -o -name '.venv*' -o -name .cache -o -name node_modules -o -path '*/dist/[!.]*' \) -prune \
    -o -name '.*' \( -name '*backup*' -o -name '*.pre-release-*' \) -prune -print0 |
    sort -z |
    while IFS= read -r -d '' path; do
        printf '%s\n' "$path"
        if [ "${1:-}" = -d ]; then rm -rf -- "$path"; fi
    done
