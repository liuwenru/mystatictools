#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
version=$(sed -n 's/^ARG INETUTILS_VERSION=//p' "${project_dir}/Dockerfile" | head -n 1)
platform=${1:-$(uname -m)}
if [ "$#" -gt 0 ]; then shift; fi
case "$platform" in
  all) architectures="amd64 arm64" ;;
  amd64 | x86_64 | linux/amd64) architectures=amd64 ;;
  arm64 | aarch64 | linux/arm64) architectures=arm64 ;;
  *)
    echo "用法: $0 [all|amd64|aarch64] [Docker 构建参数...]" >&2
    exit 2
    ;;
esac

for arch in $architectures; do
  case "$arch" in
    amd64) output_arch=x86_64 ;;
    arm64) output_arch=aarch64 ;;
  esac
  output_dir="${project_dir}/dist/${output_arch}"
  docker buildx build --builder default --platform "linux/${arch}" \
    --target artifact --output "type=local,dest=${output_dir}" \
    "$@" "${project_dir}"
  chmod 0755 "${output_dir}/telnet"
  tar -czf "${project_dir}/dist/telnet-${version}-linux-${output_arch}-static.tar.gz" \
    -C "$output_dir" telnet telnet.1 COPYING.inetutils COPYING.ncurses COPYING.shishi \
    COPYING.libtasn1 COPYING.LESSERv2.libtasn1 COPYING.libgcrypt COPYING.libgpg-error \
    COPYING.libidn BUILD-INFO README.md SHA256SUMS
  echo "产物: ${output_dir}/telnet"
done
