#!/usr/bin/env bash

set -Eeuo pipefail

# 脚本所在目录：无论从哪个目录执行，路径都不会错
SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
    pwd -P
)"

PROJECT_NAME="zsh-completion-lite"
PUBLISH_ROOT="/root/remotefs/fdoc.liuwenru/tools/zsh-completion-lite"
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

# 先在本机临时目录整理和打包，再复制到发布目录。
# 不在 sshfs 上直接打包：刚写入的文件属性更新有延迟，tar 会报
# "file changed as we read it" 并返回 1（文件内容其实已完整）。
STAGE="$(mktemp -d)"
trap 'rm -rf -- "$STAGE"' EXIT
STAGE_SOURCE="${STAGE}/${PROJECT_NAME}"

info "正在整理项目文件……"
mkdir -p "$STAGE_SOURCE"

# 包含隐藏文件，保留修改时间和软链接
cp -R --preserve=timestamps,links "${SCRIPT_DIR}/." "${STAGE_SOURCE}/"

# 发布脚本自身、测试脚本和桩数据不进入发布包
rm -f "${STAGE_SOURCE}/publish.sh"
rm -rf "${STAGE_SOURCE}/test"

info "正在生成发布包……"
tar -C "$STAGE" \
    -zcf "${STAGE}/${PROJECT_NAME}.tar.gz" \
    "$PROJECT_NAME"

info "正在复制到发布目录……"
mkdir -p "$PUBLISH_SOURCE"

# 不删除目标中的历史文件；清掉旧版本发布时留下的 test/
# 不保留权限/ACL：发布目录是 sshfs，不支持 ACL，cp -a 会报 Operation not supported
rm -rf "${PUBLISH_SOURCE}/test"
cp -R --preserve=timestamps,links "${STAGE_SOURCE}/." "${PUBLISH_SOURCE}/"
cp "${STAGE}/${PROJECT_NAME}.tar.gz" "$ARCHIVE"

success "发布完成"
printf '  源码目录：\033[1;36m%s\033[0m\n' "$PUBLISH_SOURCE"
printf '  发布包：  \033[1;36m%s\033[0m\n' "$ARCHIVE"
printf '  文件大小：\033[1;36m%s\033[0m\n' "$(du -h "$ARCHIVE" | awk '{print $1}')"
