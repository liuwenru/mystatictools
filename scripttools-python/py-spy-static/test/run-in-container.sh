#!/bin/sh
# Runs inside the test container; py-spy is mounted at /opt/py-spy, tests at /test.
set -eu

py_spy=/opt/py-spy/py-spy
work=$(mktemp -d)
trap 'kill "$pid" 2>/dev/null || true; rm -rf "$work"' EXIT
pid=

check() {
    echo "== $1"
}

check "环境: $(uname -m), $(python3 -V), $(ldd --version 2>&1 | head -n1)"
"$py_spy" --version

check "record 启动子进程 (svg)"
"$py_spy" record -d 3 -r 50 -o "$work/flame.svg" -- python3 /test/workload.py 4
grep -q python_busy_loop "$work/flame.svg"

check "record speedscope / raw 格式"
"$py_spy" record -d 2 -f speedscope -o "$work/profile.json" -- python3 /test/workload.py 3
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["shared"]["frames"]' "$work/profile.json"
"$py_spy" record -d 2 -f raw -o "$work/profile.txt" -- python3 /test/workload.py 3
grep -q python_busy_loop "$work/profile.txt"

check "attach 非子进程: dump --pid"
python3 /test/workload.py &
pid=$!
sleep 2
"$py_spy" dump --pid "$pid" > "$work/dump.txt"
cat "$work/dump.txt"
grep -q python_busy_loop "$work/dump.txt"
grep -q native_compress_loop "$work/dump.txt"

check "dump --native (libunwind 远程回溯)"
found=
for i in 1 2 3 4 5; do
    "$py_spy" dump --native --pid "$pid" > "$work/native.txt"
    # Native frames are printed with a shared-object or C source location, not .py.
    if grep -E '\((zlib|libz|deflate|.*\.so)' "$work/native.txt" | grep -qv '\.py:'; then
        found=1
        break
    fi
done
cat "$work/native.txt"
[ -n "$found" ]

check "record --native --pid"
"$py_spy" record --native -d 2 -r 50 -f raw -o "$work/native-record.txt" --pid "$pid"
# deflate comes from libz; "compress" alone would also match the Python frame.
grep -q 'deflate' "$work/native-record.txt"

check "record --subprocesses / --idle / --gil"
"$py_spy" record -d 2 --subprocesses --idle -f raw -o "$work/sub.txt" -- python3 /test/workload.py 3
"$py_spy" record -d 2 --gil -f raw -o "$work/gil.txt" -- python3 /test/workload.py 3
grep -q python_busy_loop "$work/gil.txt"

check "completions"
"$py_spy" completions bash | grep -q _py-spy

echo "全部通过"
