#!/bin/sh
# 用法: sh smoke-test.sh <file 二进制> <构建生成的 magic.mgc>
# 系统中应没有 magic 数据库，确认只依赖内嵌数据。
set -eu

file=$1
ref=$2
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
# 断言输出包含某字符串
has() { out=$1; shift; case "$out" in *"$1"*) ;; *) fail "$2: 期望含 '$1'，实际: $out" ;; esac; }

# 生成样例
printf '#!/bin/sh\necho hi\n' > script.sh
printf 'hello world, plain text line\n' > text.txt
python3 - <<'EOF'
import json, struct, zlib, zipfile, sqlite3
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 3, 8, 2, 0, 0, 0)) \
    + chunk(b"IDAT", zlib.compress(b"\x00" * 21)) + chunk(b"IEND", b"")
open("img.png", "wb").write(png)
with zipfile.ZipFile("a.zip", "w") as z:
    z.writestr("a.txt", "hello\n")
open("doc.pdf", "wb").write(b"%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n")
json.dump({"a": [1, 2, {"b": "c"}]}, open("data.json", "w"))
db = sqlite3.connect("a.db"); db.execute("create table t(x)"); db.commit(); db.close()
EOF
tar -cf a.tar text.txt
# 压缩样例 z.<压缩程序>，内容为 text.txt
for c in gzip bzip2 xz zstd lzip; do
    $c -c text.txt > "z.$c"
done
ln -s img.png link.png

# 系统中没有 magic 数据库，且清空环境（无 HOME、无 MAGIC）
run() { env -i "$file" "$@"; }

v=$(run --version)
has "$v" "magic file embedded" "--version"
pass "--version 显示使用内嵌 magic"

elf=$(run -b "$file")
case "$(uname -m)" in
    x86_64) has "$elf" "ELF 64-bit LSB executable, x86-64" "ELF 识别" ;;
    aarch64) has "$elf" "ELF 64-bit LSB executable, ARM aarch64" "ELF 识别" ;;
esac
has "$elf" "statically linked" "ELF 静态"
pass "识别自身 ELF: $elf"

has "$(run -b script.sh)" "POSIX shell script" "shell 脚本"
has "$(run -b text.txt)" "ASCII text" "文本"
has "$(run -b img.png)" "PNG image data, 2 x 3" "PNG"
has "$(run -b a.zip)" "Zip archive data" "zip"
has "$(run -b doc.pdf)" "PDF document" "PDF"
has "$(run -b data.json)" "JSON text data" "JSON"
has "$(run -b a.db)" "SQLite 3.x database" "SQLite"
has "$(run -b a.tar)" "POSIX tar archive" "tar"
pass "常见格式: 脚本、文本、PNG、zip、PDF、JSON、SQLite、tar"

[ "$(run -b --mime-type img.png)" = image/png ] || fail "mime png"
[ "$(run -b --mime-type a.zip)" = application/zip ] || fail "mime zip"
has "$(run -i text.txt)" "text/plain; charset=us-ascii" "-i"
has "$(run -b --extension img.png)" "png" "--extension"
pass "MIME（--mime-type、-i）和 --extension"

for c in gzip bzip2 xz zstd lzip; do
    plain=$(run -b "z.$c")
    case "$plain" in *"ASCII text"*) fail "$c 样例未压缩: $plain" ;; esac
    has "$(run -b -z "z.$c")" "ASCII text" "-z $c"
    [ "$(run -b -Z --mime-type "z.$c")" = text/plain ] || fail "-Z $c"
    echo "  $c: $plain"
done
pass "内置解压 -z/-Z（gzip、bzip2、xz、zstd、lzip）"

# lz4 没有内置库，-z 时 fork 外部 lz4 命令；找不到命令时只显示外层格式
lz4 -q -c text.txt > z.lz4
has "$(env -i PATH="$PATH" "$file" -b -z z.lz4)" "ASCII text" "-z lz4（外部命令）"
has "$(env -i PATH=/nonexistent "$file" -b -z z.lz4)" "LZ4 compressed data" "无 lz4 命令"
pass "-z 调用外部 lz4 命令；PATH 中没有时退回只显示外层格式"

has "$(cat img.png | run -b -)" "PNG image data" "stdin 管道"
has "$(run -b link.png)" "symbolic link to img.png" "符号链接 -h"
has "$(run -b -L link.png)" "PNG image data" "-L 跟随链接"
has "$(run -k -b "$file")" "ELF" "-k"
printf 'img.png\na.zip\n' > list
[ "$(run -b -f list | wc -l)" -eq 2 ] || fail "-f"
has "$(run -s -b /dev/null)" "empty" "-s 设备"
pass "stdin、符号链接、-k、-f、-s"

# 内嵌数据库与构建生成的 magic.mgc 输出一致
for f in "$file" script.sh text.txt img.png a.zip doc.pdf data.json a.db a.tar z.gzip z.xz z.zstd z.lzip /bin/busybox /usr/lib/libz.a /usr/bin/python3; do
    a=$(run -b "$f"); b=$(run -b -m "$ref" "$f")
    [ "$a" = "$b" ] || fail "内嵌与 $ref 输出不同: $f"
done
pass "内嵌 magic 与构建生成的 magic.mgc 结果一致"

# -m 和 MAGIC 环境变量可以覆盖内嵌数据库
printf '0\tstring\tHELLOMAGIC\tcustom hello format\n' > custom
printf 'HELLOMAGIC data\n' > sample.hm
has "$(run -b -m custom sample.hm)" "custom hello format" "-m 自定义"
has "$(env -i MAGIC="$work/custom" "$file" -b sample.hm)" "custom hello format" "MAGIC 环境变量"
has "$(env -i MAGIC="$work/custom" "$file" --version)" "magic file from $work/custom" "MAGIC 时 --version"
if env -i MAGIC=/nonexistent "$file" text.txt >/dev/null 2>&1; then fail "MAGIC 指向不存在文件应失败"; fi
pass "-m、MAGIC 覆盖内嵌数据库；MAGIC 无效时报错，不回退到内嵌"

# -C 编译、-c 检查需要显式 -m
run -C -m custom >/dev/null && [ -s custom.mgc ] || fail "-C 编译"
has "$(run -b -m custom.mgc sample.hm)" "custom hello format" "使用 -C 编译结果"
run -c -m custom >/dev/null 2>&1 || fail "-c 检查"
pass "-C 编译、-c 检查自定义 magic"

echo "全部测试通过"
