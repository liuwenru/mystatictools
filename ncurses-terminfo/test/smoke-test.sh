#!/bin/sh
# 测试打包目录中的程序、预编译数据库和 install.sh。
# 用法: sh smoke-test.sh <包目录>；运行前应删除系统 terminfo，确认只依赖包内文件。
set -eu

pkg=$(CDPATH= cd -- "$1" && pwd)
bin=$pkg/bin
db=$pkg/share/terminfo
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

for d in /etc/terminfo /lib/terminfo /usr/share/terminfo; do
    [ ! -e "$d" ] || fail "系统 terminfo 未删除: $d"
done

# 传统格式 magic 为八进制 0432（小端字节 1a 01）；扩展数值格式为 01036（1e 02）。
magic() { od -An -tx1 -N2 "$1" | tr -d ' \n'; }
[ "$(magic "$db/t/tmux-256color")" = 1a01 ] || fail "tmux-256color 不是传统格式"
pass "预编译 tmux-256color 为传统格式"
"$bin/infocmp" -A "$db" tmux-256color | grep -q 'pairs#0x7fff' || fail "pairs 未截断为 0x7fff"
pass "pairs#0x10000 截断为 0x7fff"
for f in $(find "$db" -type f); do
    m=$(magic "$f")
    [ "$m" = 1a01 ] || fail "$f magic=$m"
done
pass "全部 $(find "$db" -type f | wc -l) 个预编译文件为传统格式"

# 别名为相对软链接，复制或解压到别处后仍可用。
[ -L "$db/x/xterm-kitty" ] || fail "xterm-kitty 不是软链接"
case "$(readlink "$db/x/xterm-kitty")" in /*) fail "软链接是绝对路径" ;; esac
[ -z "$(find "$db" -type l ! -exec test -e {} \; -print)" ] || fail "存在失效软链接"
pass "别名为相对软链接且无失效链接"

# tput/clear 只靠 TERMINFO_DIRS 查找包内数据库。
export TERMINFO_DIRS="$db"
[ "$(TERM=tmux-256color "$bin/tput" colors)" = 256 ] || fail "tmux-256color colors"
[ "$(TERM=xterm-kitty "$bin/tput" colors)" = 256 ] || fail "xterm-kitty colors"
[ "$(TERM=xterm-ghostty "$bin/tput" colors)" = 256 ] || fail "xterm-ghostty colors"
[ "$(TERM=xterm-256color "$bin/tput" setaf 1 | od -An -c | tr -d ' \n')" = '033[31m' ] \
    || fail "setaf 1 输出不正确"
[ "$(TERM=xterm "$bin/clear" | od -An -c | tr -d ' \n')" = '033[H033[2J033[3J' ] \
    || fail "clear 输出不正确"
TERM=linux "$bin/tput" cup 1 1 >/dev/null || fail "linux cup"
TERM=xterm-256color "$bin/infocmp" -x | grep -q '^xterm-256color|' || fail "infocmp 读取当前 TERM"
unset TERMINFO_DIRS
pass "tput/clear/infocmp 使用 TERMINFO_DIRS 中的包内数据库"

# install.sh 按名称安装，默认写入 ~/.terminfo，ncurses 能从该目录读取（root 下也是）。
HOME=$work/home sh "$pkg/install.sh" tmux-256color xterm-kitty xterm-ghostty 2>"$work/err"
[ ! -s "$work/err" ] || fail "按名称安装输出了无关警告: $(head -n 3 "$work/err")"
[ -f "$work/home/.terminfo/t/tmux-256color" ] || fail "未写入 ~/.terminfo"
[ "$(magic "$work/home/.terminfo/t/tmux-256color")" = 1a01 ] || fail "安装结果不是传统格式"
[ "$(HOME=$work/home TERM=xterm-kitty "$bin/tput" colors)" = 256 ] || fail "从 ~/.terminfo 读取"
pass "install.sh 按名称安装到 ~/.terminfo"

# 指定目录；只写入所列条目及其别名，不写入 use= 引用的其他条目。
sh "$pkg/install.sh" -o "$work/dir" tmux-256color >/dev/null
[ ! -e "$work/dir/x/xterm-256color" ] || fail "写入了未列出的条目"
"$bin/infocmp" -x -A "$db" tmux-256color | sed 1d > "$work/a"
"$bin/infocmp" -x -A "$work/dir" tmux-256color | sed 1d > "$work/b"
cmp -s "$work/a" "$work/b" || fail "安装结果与包内数据库不一致"
pass "install.sh -o 只写入所列条目，内容与包内数据库一致"

# 用 infocmp -x 导出后再 -f 安装，内容不变。
"$bin/infocmp" -x -A "$db" xterm-ghostty > "$work/ghostty.src"
sh "$pkg/install.sh" -o "$work/file" -f "$work/ghostty.src" >/dev/null
"$bin/infocmp" -x -A "$db" xterm-ghostty | sed 1d > "$work/a"
"$bin/infocmp" -x -A "$work/file" xterm-ghostty | sed 1d > "$work/b"
cmp -s "$work/a" "$work/b" || fail "-f 安装结果不一致"
pass "install.sh -f 安装 infocmp -x 导出的文件"

if sh "$pkg/install.sh" -o "$work/bad" no-such-term 2>/dev/null; then fail "未知终端应失败"; fi
if sh "$pkg/install.sh" -o relative tmux-256color 2>/dev/null; then fail "相对路径应失败"; fi
pass "未知终端名和相对路径会报错"

sh "$pkg/install.sh" -l | grep -qE '^ghostty\|xterm-ghostty[[:space:]]+Ghostty' || fail "-l 未列出 xterm-ghostty"
pass "install.sh -l 列出 $(sh "$pkg/install.sh" -l | wc -l) 个条目"

"$bin/infocmp" -A "$db" -C vt100 | grep -q '^vt100|' || fail "infocmp -C"
"$bin/infocmp" -A "$db" vt100 > "$work/vt100.src"
"$bin/infotocap" "$work/vt100.src" 2>/dev/null | grep -q '^vt100|' || fail "infotocap"
"$bin/toe" "$db" | grep -q '^tmux-256color' || fail "toe"
pass "infocmp -C、infotocap、toe 正常"

echo "全部测试通过"
