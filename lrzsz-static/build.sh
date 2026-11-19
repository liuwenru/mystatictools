#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
version=$(sed -n 's/^ARG LRZSZ_VERSION=//p' "$project_dir/Dockerfile")
platform=${1:-$(uname -m)}
if [ "$#" -gt 0 ]; then shift; fi
case "$platform" in
  amd64|x86_64|linux/amd64) arch=amd64; output_arch=x86_64 ;;
  arm64|aarch64|linux/arm64) arch=arm64; output_arch=aarch64 ;;
  *) echo "用法: $0 [amd64|aarch64] [Docker 构建参数...]" >&2; exit 2 ;;
esac

output_dir="$project_dir/dist/$output_arch"
mkdir -p "$output_dir"
# SSHFS 无法恢复部分符号链接元数据；tar 解包跳过属主和时间戳。
export_tar="$project_dir/dist/.export-$output_arch-$$.tar"
docker buildx build --builder default --platform "linux/$arch" \
  --target artifact --output "type=tar,dest=$export_tar" "$@" "$project_dir"
tar --no-same-owner -m -xf "$export_tar" -C "$output_dir"
rm -f "$export_tar"
chmod 0755 "$output_dir/lrz" "$output_dir/lsz"
(cd "$output_dir" && sha256sum -c SHA256SUMS)
tar -czf "$project_dir/dist/lrzsz-$version-linux-$output_arch-static.tar.gz" \
  -C "$output_dir" lrz lsz rz sz rx sx rb sb lrx lsx lrb lsb COPYING lrz.1 lsz.1 SHA256SUMS
echo "产物: $output_dir"
