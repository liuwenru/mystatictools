#!/bin/sh
# 用包内静态 tic 把终端定义编译到目标机的 terminfo 目录。
#
#   ./install.sh [-o 目录] 终端名...         从包内 share/terminfo.src 编译指定条目
#   ./install.sh [-o 目录] -f 文件.src...     编译 infocmp -x 导出的文件
#   ./install.sh [-o 目录] -a                编译 terminfo.src 全部条目
#   ./install.sh -l                          列出包内全部条目
#
# 默认目录：设置了 TERMINFO 时用它，否则用 ~/.terminfo。
# 系统级安装需 root 并显式指定，例如 -o /usr/share/terminfo。
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
tic="$here/bin/tic"
infocmp="$here/bin/infocmp"
src="$here/share/terminfo.src"
db="$here/share/terminfo"

usage() {
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-2}"
}

dest=${TERMINFO:-${HOME:-}/.terminfo}
mode=names
while getopts o:falh opt; do
    case "$opt" in
        o) dest=$OPTARG ;;
        f) mode=files ;;
        a) mode=all ;;
        l) mode=list ;;
        h) usage 0 ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

if [ "$mode" = list ]; then
    # 每行：全部名字（含别名，| 分隔） 说明
    awk -F'|' '/^[^#[:space:]]/ {
        sub(/,[[:space:]]*$/, ""); n = split($0, a, "|")
        if (n == 1) { print a[1]; next }
        names = a[1]; for (i = 2; i < n; i++) names = names "|" a[i]
        printf "%-40s %s\n", names, a[n]
    }' "$src"
    exit 0
fi
if [ "$mode" != all ] && [ "$#" -eq 0 ]; then
    usage
fi
case "$dest" in
    /*) ;;
    *) echo "目标目录需为绝对路径: $dest" >&2; exit 2 ;;
esac
mkdir -p "$dest"

# 编译 terminfo.src 时 tic 会对无关条目提示数值截断（见 README），只在失败时显示。
quiet_tic() {
    log=$(mktemp)
    if ! "$tic" "$@" 2>"$log"; then
        cat "$log" >&2
        rm -f "$log"
        exit 1
    fi
    rm -f "$log"
}

case "$mode" in
    all)
        quiet_tic -x -o "$dest" "$src"
        echo "已编译 terminfo.src 全部条目到 $dest"
        ;;
    files)
        for f in "$@"; do
            "$tic" -x -o "$dest" "$f"
            echo "已编译 $f 到 $dest"
        done
        ;;
    names)
        for name in "$@"; do
            if ! "$infocmp" -A "$db" "$name" >/dev/null 2>&1; then
                echo "包内没有终端定义: $name（可用 -l 查看全部条目）" >&2
                exit 1
            fi
        done
        list=$(printf '%s,' "$@")
        quiet_tic -x -e "${list%,}" -o "$dest" "$src"
        for name in "$@"; do
            "$infocmp" -A "$dest" "$name" >/dev/null
            echo "已安装 $name 到 $dest"
        done
        ;;
esac

case "$dest" in
    "${HOME:-/nonexistent}/.terminfo"|/etc/terminfo|/lib/terminfo|/usr/share/terminfo) ;;
    *) echo "该目录不是默认查找路径，使用前执行: export TERMINFO_DIRS=$dest:" ;;
esac
