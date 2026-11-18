#!/bin/bash
set -e
cd "$(dirname "$0")"

dest=/root/remotefs/fdoc.liuwenru/tools/static_tools
for arch in x86_64 aarch64; do
  (cd "dist/$arch" && sha256sum -c SHA256SUMS)
done
for arch in x86_64 aarch64; do
  for name in lrz lsz rz sz rx sx rb sb lrx lsx lrb lsb; do
    cp "dist/$arch/$name" "$dest/$arch/$name"
    chmod 0755 "$dest/$arch/$name"
    cmp "dist/$arch/$name" "$dest/$arch/$name"
  done
done
"$dest/archive.sh"
