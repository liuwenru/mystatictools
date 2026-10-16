#!/usr/bin/env bash

set -Eeuo pipefail

# 脚本所在目录：无论从哪个目录执行，路径都不会错
SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
    pwd -P
)"

PROJECT_NAME="bash-completion-lite"
PUBLISH_ROOT="/root/remotefs/fdoc.liuwenru/tools/bash-completion-lite"
PUBLISH_SOURCE="${PUBLISH_ROOT}/${PROJECT_NAME}"
ARCHIVE="${PUBLISH_ROOT}/${PROJECT_NAME}.tar.gz"

info() {
    printf '\033[1;34m[INFO]\033[0m %s\n' "$*"
}

success() {
    printf '\033[1;32m[SUCCESS]\033[0m %s\n' "$*"
}

error() {
    printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2
}

trap 'error "发布失败（命令所在行：${LINENO}）"' ERR

info "项目目录：${SCRIPT_DIR}"
info "发布目录：${PUBLISH_ROOT}"

mkdir -p "$PUBLISH_ROOT"

info "正在复制项目文件……"
mkdir -p "$PUBLISH_SOURCE"

# 包含隐藏文件，并保留权限和软链接；不会删除目标中的历史文件
cp -a "${SCRIPT_DIR}/." "${PUBLISH_SOURCE}/"

# 防止把发布脚本自身复制进发布包；如需保留可删除这一行
rm -f "${PUBLISH_SOURCE}/publish.sh"

info "正在生成发布包……"
tar -C "$PUBLISH_ROOT" \
    -zcf "$ARCHIVE" \
    "$PROJECT_NAME"

success "发布完成"
printf '  源码目录：\033[1;36m%s\033[0m\n' "$PUBLISH_SOURCE"
printf '  发布包：  \033[1;36m%s\033[0m\n' "$ARCHIVE"
printf '  文件大小：\033[1;36m%s\033[0m\n' "$(du -h "$ARCHIVE" | awk '{print $1}')"
