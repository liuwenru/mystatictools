#!/bin/sh
set -e
cd "$(dirname "$0")"
dest=/root/remotefs/fdoc.liuwenru/tools/static_tools
for arch in x86_64 aarch64; do
  (cd "dist/$arch" && sha256sum -c SHA256SUMS)
done
for arch in x86_64 aarch64; do
  cp "dist/$arch/telnet" "$dest/$arch/"
  cmp "dist/$arch/telnet" "$dest/$arch/telnet"
  test -x "$dest/$arch/telnet"
done
"$dest/archive.sh"
