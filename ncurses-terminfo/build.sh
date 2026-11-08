#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
version=$(sed -n 's/^ARG NCURSES_VERSION=//p' "${project_dir}/Dockerfile" | head -n 1)
platform=${1:-$(uname -m)}
if [ "$#" -gt 0 ]; then shift; fi
case "$platform" in
    all) architectures="amd64 arm64" ;;
    amd64|x86_64|linux/amd64) architectures=amd64 ;;
    arm64|aarch64|linux/arm64) architectures=arm64 ;;
    *) echo "用法: $0 [all|amd64|aarch64] [Docker 构建参数...]" >&2; exit 2 ;;
esac

# 产物含大量软链接（terminfo 别名、reset、captoinfo、infotocap）。ARM 主机通过 SSHFS 访问 dist/，
# type=local 导出对软链接 lchown 会失败。与 node-static 相同：先导出到本机临时目录打包，
# 再把压缩包复制到 dist/，并用 --no-same-owner 解压一份供检查。
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for arch in $architectures; do
    case "$arch" in
        amd64) output_arch=x86_64 ;;
        arm64) output_arch=aarch64 ;;
    esac
    output_dir="${project_dir}/dist/${output_arch}"
    package="ncurses-terminfo-${version}-linux-${output_arch}.tar.gz"
    rm -rf "${work:?}/root" "${work}/export.tar"
    mkdir -p "${work}/root"
    docker buildx build --builder default --platform "linux/${arch}" \
        --target artifact --output "type=tar,dest=${work}/export.tar" \
        "$@" "${project_dir}"
    tar -x --no-same-owner -f "${work}/export.tar" -C "${work}/root"
    test -x "${work}/root/ncurses-terminfo/bin/tic"
    test -L "${work}/root/ncurses-terminfo/share/terminfo/x/xterm-kitty"
    tar -czf "${work}/${package}" --owner=0 --group=0 -C "${work}/root" ncurses-terminfo
    (cd "$work" && sha256sum "$package" > "${package}.sha256")
    mkdir -p "${project_dir}/dist"
    cp "${work}/${package}" "${work}/${package}.sha256" "${project_dir}/dist/"
    rm -rf "$output_dir"
    mkdir -p "$output_dir"
    tar -x --no-same-owner -f "${work}/${package}" -C "$output_dir"
    echo "产物: ${project_dir}/dist/${package}"
done
