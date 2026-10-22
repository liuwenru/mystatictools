#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
platform=${1:-all}
if [ "$#" -gt 0 ]; then shift; fi
case "$platform" in
    all) architectures="amd64 arm64" ;;
    amd64|x86_64|linux/amd64) architectures=amd64 ;;
    arm64|aarch64|linux/arm64) architectures=arm64 ;;
    *) echo "用法: $0 [all|amd64|aarch64] [Docker 构建参数...]" >&2; exit 2 ;;
esac
for arch in $architectures; do
    case "$arch" in
        amd64) output_arch=x86_64 ;;
        arm64) output_arch=aarch64 ;;
    esac
    output_dir="${project_dir}/dist/${output_arch}"
    docker buildx build --builder default --platform "linux/${arch}" \
        --target artifact --output "type=local,dest=${output_dir}" "$@" "$project_dir"
    chmod 0755 "${output_dir}/nvim/bin/nvim"
    tar -czf "${project_dir}/dist/nvim-linux-${output_arch}.tar.gz" -C "$output_dir" nvim
    tar -czf "${project_dir}/dist/nvim-sources-${output_arch}.tar.gz" -C "$output_dir" sources
    echo "产物: ${project_dir}/dist/nvim-linux-${output_arch}.tar.gz"
done
