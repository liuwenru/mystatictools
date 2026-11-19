#!/bin/bash
set -e
cd "$(dirname "$0")"

dest=/root/remotefs/fdoc.liuwenru/tools/neovim
printf '发布目录：%s\n' "$dest"

SECONDS=0
step=0
for arch in aarch64 x86_64; do
  file="nvim-linux-${arch}.tar.gz"
  step=$((step + 1))
  started=$SECONDS
  printf '[%d/2] 正在复制 %s …\n' "$step" "$file"
  cp "dist/$file" "$dest/$file"
  printf '[%d/2] 复制完成：%s（%d 秒）\n' "$step" "$file" "$((SECONDS - started))"
done

printf '两个运行包均已复制，总耗时 %d 秒。\n' "$SECONDS"
