#!/bin/sh
# 在无 musl、断网的 glibc 容器中验证 dist/<arch>/py-spy。
# 用法: test/smoke-test.sh [x86_64|aarch64] [镜像]
set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
arch=${1:-$(uname -m)}
image=${2:-python:3.12-slim}
case "$arch" in
    x86_64|amd64) arch=x86_64; platform=linux/amd64 ;;
    aarch64|arm64) arch=aarch64; platform=linux/arm64 ;;
    *) echo "用法: $0 [x86_64|aarch64] [镜像]" >&2; exit 2 ;;
esac
bin_dir="${test_dir}/../dist/${arch}"

readelf -h "${bin_dir}/py-spy" | grep -E 'Class|Machine'
! readelf -lW "${bin_dir}/py-spy" | grep -q INTERP
! readelf -d "${bin_dir}/py-spy" | grep -q '(NEEDED)'
(cd "$bin_dir" && sha256sum -c SHA256SUMS)

# py-spy 读取其他进程内存需要 ptrace 权限；只额外授予 SYS_PTRACE。
docker run --rm --network none --platform "$platform" --cap-add SYS_PTRACE \
    -v "${bin_dir}:/opt/py-spy:ro" -v "${test_dir}:/test:ro" \
    "$image" sh /test/run-in-container.sh
