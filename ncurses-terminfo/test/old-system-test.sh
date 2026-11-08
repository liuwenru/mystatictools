#!/bin/sh
# 在老发行版容器中，用系统自带的 ncurses（不是包内程序）读取本包生成的 terminfo。
# 用法: test/old-system-test.sh [x86_64|aarch64]，可在任意目录运行。
# 需要能拉取 centos:7、ubuntu:16.04 镜像；容器以 --rm、断网运行，只读挂载解压后的发布包。
# 发布包解压到本机临时目录：ARM 主机经 SSHFS 读取 dist/ 时软链接不可用。
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
arch=${1:-$(uname -m)}
version=$(sed -n 's/^ARG NCURSES_VERSION=//p' "${project_dir}/Dockerfile" | head -n 1)
package="${project_dir}/dist/ncurses-terminfo-${version}-linux-${arch}.tar.gz"
[ -f "$package" ] || { echo "缺少产物: ${package}" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tar -x --no-same-owner -f "$package" -C "$work"
pkg="${work}/ncurses-terminfo"

# 对照组：当前宿主机 ncurses 编译的 tmux-256color（若为扩展格式，老系统应读不了）。
host_entry=$(find /usr/share/terminfo /lib/terminfo -name tmux-256color 2>/dev/null | head -n 1 || true)

for image in centos:7 ubuntu:16.04; do
    echo "=== ${image}"
    docker run --rm --network none \
        -v "${pkg}:/pkg:ro" \
        ${host_entry:+-v "${host_entry}:/host-tmux-256color:ro"} \
        "${image}" sh -eu -c '
            infocmp -V
            for t in tmux-256color xterm-kitty xterm-ghostty foot alacritty wezterm; do
                # 系统 tput 读取包内预编译数据库
                c=$(TERMINFO_DIRS=/pkg/share/terminfo TERM=$t tput colors)
                echo "PASS: 系统 tput 读取包内 $t colors=$c"
            done
            # 包内 install.sh 编译到 ~/.terminfo，再由系统 ncurses 读取
            export HOME=$(mktemp -d)
            sh /pkg/install.sh tmux-256color xterm-kitty >/dev/null
            TERM=tmux-256color tput setaf 1 | od -c | head -n 1
            TERM=xterm-kitty infocmp -x | head -n 2
            echo "PASS: install.sh 安装后系统 ncurses 可读"
            if [ -e /host-tmux-256color ]; then
                mkdir -p /tmp/host/t && cp /host-tmux-256color /tmp/host/t/
                # -A 只查指定目录，避免回退到 ~/.terminfo 或系统目录
                if infocmp -A /tmp/host tmux-256color >/dev/null 2>&1; then
                    echo "对照: 宿主机编译的 tmux-256color 可读"
                else
                    echo "对照: 宿主机编译的 tmux-256color 读取失败（扩展数值格式）"
                fi
            fi
        '
done
