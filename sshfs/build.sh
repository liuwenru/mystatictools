#!/bin/sh
# 构建 sshfs 静态包并导出到 dist/<架构>/
#   ./build.sh            # 当前主机架构
#   ./build.sh aarch64    # 指定架构：amd64|x86_64|arm64|aarch64|all
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
platform=${1:-$(uname -m)}
if [ "$#" -gt 0 ]; then
    shift
fi

case "$platform" in
    all) architectures="amd64 arm64" ;;
    amd64|x86_64|linux/amd64) architectures=amd64 ;;
    arm64|aarch64|linux/arm64) architectures=arm64 ;;
    *) echo "用法: $0 [all|amd64|x86_64|arm64|aarch64] [Docker 构建参数...]" >&2; exit 2 ;;
esac

for arch in $architectures; do
    case "$arch" in
        amd64) output_arch=x86_64 ;;
        arm64) output_arch=aarch64 ;;
    esac
    output_dir="${project_dir}/dist/${output_arch}"
    docker buildx build \
        --builder default \
        --platform "linux/${arch}" \
        --target artifact \
        --output "type=local,dest=${output_dir}" \
        "$@" \
        "${project_dir}"
    chmod 0755 "$output_dir"
    (cd "$output_dir" && sha256sum -c SHA256SUMS)
    package="${project_dir}/dist/sshfs-tools-${output_arch}.tar.gz"
    tar -czf "$package" --owner=0 --group=0 --numeric-owner \
        --transform "s|^${output_arch}|sshfs-tools-${output_arch}|;s|^README.md|sshfs-tools-${output_arch}/README.md|" \
        -C "${project_dir}/dist" "${output_arch}" \
        -C "${project_dir}" README.md
    echo "产物: ${output_dir}"
    echo "发布包: ${package}"
done
