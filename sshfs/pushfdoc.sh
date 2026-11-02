#!/bin/bash
# 发布到 fdoc；覆盖前把旧包备份为同目录隐藏文件
set -eu
cd "$(dirname "$0")"
dest=/root/remotefs/fdoc.liuwenru/tools/sshfs
stamp=$(date +%Y-%m-%d-%H-%M-%S)
for arch in x86_64 aarch64; do
    name=sshfs-tools-${arch}.tar.gz
    if [ -e "$dest/$name" ]; then
        cp -p "$dest/$name" "$dest/.${name}.pre-release-${stamp}"
    fi
    cp "dist/$name" "$dest/$name"
done
