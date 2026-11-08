#!/bin/sh
# 在老发行版容器中运行静态 file，确认使用内嵌 magic，不受系统旧版 magic 数据库影响。
# 用法: test/old-system-test.sh [x86_64|aarch64]，可在任意目录运行。
# 需要能拉取 centos:7、ubuntu:16.04 镜像；容器以 --rm、断网运行，只读挂载产物。
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
arch=${1:-$(uname -m)}
bin="${project_dir}/dist/${arch}/file"
[ -x "$bin" ] || { echo "缺少产物: ${bin}" >&2; exit 1; }

for image in centos:7 ubuntu:16.04; do
    echo "=== ${image}"
    docker run --rm --network none -v "${bin}:/static/file:ro" "${image}" sh -eu -c '
        if command -v file >/dev/null; then
            echo "系统 file: $(file --version 2>&1 | head -n 1)"
        else
            echo "系统 file: 未安装"
        fi
        cd "$(mktemp -d)"
        printf "{\"a\": 1}\n" > a.json
        printf "hello\n" > t && gzip -c t > t.gz
        for f in /static/file /bin/sh a.json t.gz; do
            echo "  $f: $(/static/file -b "$f")"
        done
        /static/file --version | grep -q "magic file embedded"
        /static/file -b a.json | grep -q "JSON text data"
        /static/file -b -z t.gz | grep -q "ASCII text"
        echo "PASS: 静态 file 使用内嵌 magic，JSON 识别和 -z 正常"
    '
done
