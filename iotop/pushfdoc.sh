#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

dest=/root/remotefs/fdoc.liuwenru/tools/static_tools
cmp dist/x86_64/VERSION dist/aarch64/VERSION
for arch in x86_64 aarch64; do
  (cd "dist/$arch" && sha256sum -c SHA256SUMS && test -x iotop)
  if [ ! -d "$dest/$arch" ] || [ ! -w "$dest/$arch" ]; then
    printf 'Missing or unwritable publish directory: %s\n' "$dest/$arch" >&2
    exit 1
  fi
done
if [ ! -x "$dest/archive.sh" ]; then
  printf 'Missing or non-executable archive script: %s\n' "$dest/archive.sh" >&2
  exit 1
fi

for arch in x86_64 aarch64; do
  cp "dist/$arch/iotop" "$dest/$arch/iotop"
  chmod 0755 "$dest/$arch/iotop"
  cmp "dist/$arch/iotop" "$dest/$arch/iotop"
  test -x "$dest/$arch/iotop"
done
"$dest/archive.sh"
for arch in x86_64 aarch64; do
  tar -xzOf "$dest/${arch}_static_tools.tar.gz" ./iotop | cmp "dist/$arch/iotop" -
done
