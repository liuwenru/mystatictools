#!/bin/bash
set -e
cd "$(dirname "$0")"

dest=/root/remotefs/fdoc.liuwenru/tools/static_tools

cp dist/x86_64/file "$dest/x86_64/"
cp dist/aarch64/file "$dest/aarch64/"

# 重新生成 <架构>_static_tools.tar.gz
"$dest/archive.sh"
