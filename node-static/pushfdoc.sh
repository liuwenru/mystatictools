#!/bin/bash
set -e
cd "$(dirname "$0")"

dest=/root/remotefs/fdoc.liuwenru/tools/node
mkdir -p "$dest"
for arch in x86_64 aarch64; do
    cp dist/node-v26.13.0-linux-${arch}-static.tar.gz "$dest/"
    cp dist/node-v26.13.0-linux-${arch}-static.tar.gz.sha256 "$dest/"
done
