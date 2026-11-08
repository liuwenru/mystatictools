#!/bin/bash
set -e
cd "$(dirname "$0")"

dest=/root/remotefs/fdoc.liuwenru/tools/ncurses-terminfo
mkdir -p "$dest"
for arch in x86_64 aarch64; do
    (cd dist && sha256sum -c "ncurses-terminfo-6.6-linux-${arch}.tar.gz.sha256")
    cp dist/ncurses-terminfo-6.6-linux-${arch}.tar.gz "$dest/"
    cp dist/ncurses-terminfo-6.6-linux-${arch}.tar.gz.sha256 "$dest/"
done
