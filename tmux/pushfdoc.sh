#!/bin/bash
set -e
cd "$(dirname "$0")"

dest=/root/remotefs/fdoc.liuwenru/tools/static_tools

# 只复制 tmux 本体，dist/ 中的调试日志等文件不发布
cp dist/x86_64/tmux "$dest/x86_64/"
cp dist/aarch64/tmux "$dest/aarch64/"

# 重新生成 <架构>_static_tools.tar.gz
"$dest/archive.sh"
