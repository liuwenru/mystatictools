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
node_version=$(sed -n 's/^ARG NODE_VERSION=//p' "${project_dir}/Dockerfile" | head -n 1)
# 产物含 bin/npm、bin/npx 软链接。ARM 主机通过 SSHFS 访问 dist/：type=local 导出对软链接
# lchown 会失败，从 SSHFS 读回软链接也会失败。所以先在本机临时目录解压、检查、打包，
# 再写入 dist/，不从共享目录读回软链接。
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for arch in $architectures; do
    case "$arch" in
        amd64) output_arch=x86_64 ;;
        arm64) output_arch=aarch64 ;;
    esac
    output_dir="${project_dir}/dist/${output_arch}"
    rm -rf "${work:?}/root" "${work}/export.tar"
    mkdir -p "${work}/root"
    docker buildx build --builder default --platform "linux/${arch}" \
        --target artifact --output "type=tar,dest=${work}/export.tar" "$@" "$project_dir"
    tar -x --no-same-owner -f "${work}/export.tar" -C "${work}/root"
    # 标记文件只用于确认 scratch 断网测试已执行，不打进运行包。
    test -f "${work}/root/node-offline-test.ok"
    chmod 0755 "${work}/root/node/bin/node"
    test -L "${work}/root/node/bin/npm" && test -L "${work}/root/node/bin/npx"
    mkdir -p "${project_dir}/dist"
    package="node-v${node_version}-linux-${output_arch}-static.tar.gz"
    tar -czf "${work}/${package}" -C "${work}/root" node
    (cd "$work" && sha256sum "$package" > "${package}.sha256")
    cp "${work}/${package}" "${work}/${package}.sha256" "${project_dir}/dist/"
    rm -rf "$output_dir"
    mkdir -p "$output_dir"
    tar -x --no-same-owner -f "${work}/${package}" -C "$output_dir"
    echo "产物: ${project_dir}/dist/${package}"
done
