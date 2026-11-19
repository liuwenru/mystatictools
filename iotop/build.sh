#!/bin/sh
set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
platform=${1:-$(uname -m)}
if [ "$#" -gt 0 ]; then shift; fi
case "$platform" in
  amd64|x86_64|linux/amd64) arch=amd64; output_arch=x86_64 ;;
  arm64|aarch64|linux/arm64) arch=arm64; output_arch=aarch64 ;;
  *) printf 'Usage: %s [amd64|aarch64] [Docker build arguments...]\n' "$0" >&2; exit 2 ;;
esac

dist="$project_dir/dist"
mkdir -p "$dist/$output_arch"
stage=$(mktemp -d "$dist/.build-$output_arch.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
trap 'exit 1' HUP INT TERM
# Export through tar to avoid restoring SSHFS metadata from the build container.
docker buildx build --builder default --platform "linux/$arch" \
  --target artifact --output "type=tar,dest=$stage/export.tar" "$@" "$project_dir"
tar --no-same-owner -m -xf "$stage/export.tar" -C "$stage"
(
  cd "$stage"
  sha256sum -c SHA256SUMS
  tar -czf package.tar.gz iotop iotop.8 COPYING LICENSE ncurses.COPYING VERSION SHA256SUMS
)
version=$(tr -d '\n' < "$stage/VERSION")
cp "$stage/iotop" "$stage/iotop.8" "$stage/COPYING" "$stage/LICENSE" "$stage/ncurses.COPYING" \
  "$stage/VERSION" "$stage/SHA256SUMS" "$dist/$output_arch/"
chmod 0755 "$dist/$output_arch/iotop"
mv "$stage/package.tar.gz" "$dist/iotop-$version-linux-$output_arch-static.tar.gz"
printf 'Package: %s\n' "$dist/iotop-$version-linux-$output_arch-static.tar.gz"
