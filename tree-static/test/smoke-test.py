#!/usr/bin/env python3
"""在无共享库、shell、locale 数据的临时 chroot 中测试；需要 root（chroot、chown）。"""
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

binary = Path(sys.argv[1]).resolve()
version = "2.3.2"
old_time = 978307200  # 2001-01-01 00:00:00 UTC


def check(name, condition, detail=""):
    if not condition:
        raise AssertionError(f"{name}\n{detail}")
    print(f"PASS: {name}", flush=True)


with tempfile.TemporaryDirectory(prefix="tree-test-") as directory:
    root = Path(directory)
    for d in ("etc", "tmp", "work"):
        (root / d).mkdir()
    (root / "etc/passwd").write_text("root:x:0:0::/:/nonexistent\nalice:x:1234:1234::/:/nonexistent\n")
    (root / "etc/group").write_text("root:x:0:\nops:x:1234:\n")
    shutil.copy2(binary, root / "tree")

    # 固定内容的测试目录，名字只用 ASCII，便于逐字比较输出。
    t = root / "work/t"
    for d in ("a/b", "deep/x/y", "src"):
        (t / d).mkdir(parents=True)
    (t / "a/b/f.txt").write_text("hi\n")
    (t / "big.bin").write_bytes(b"x" * 2000)
    (t / "deep/x/y/z.c").touch()
    (t / "src/main.c").touch()
    (t / "src/util.h").touch()
    (t / "src/README").touch()
    (t / ".hidden").touch()
    (t / "link").symlink_to("a")
    (t / "loop").symlink_to(".")
    os.chown(t / "src/main.c", 1234, 1234)
    os.chown(t / "src/util.h", 4321, 4321)
    os.utime(t / "big.bin", (old_time, old_time))

    # 非 ASCII 和不可打印文件名单独放，避免影响 XML/JSON 解析。
    odd = root / "work/odd"
    odd.mkdir()
    for name in ("中文.txt".encode(), b"bad\xffname", b"nl\nname"):
        (odd / os.fsdecode(name)).touch()

    def enter_chroot():
        os.chroot(root)
        os.chdir("/work")

    def run(*args, env=None, code=0):
        result = subprocess.run(
            ["/tree", *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            preexec_fn=enter_chroot, env={} if env is None else env, timeout=30,
        )
        if result.returncode != code:
            raise AssertionError(f"tree {args}: exit {result.returncode}\n"
                                 + result.stdout.decode(errors="replace")
                                 + result.stderr.decode(errors="replace"))
        return result.stdout

    def text(*args, env=None, code=0):
        return run(*args, env=env, code=code).decode()

    out = text("--version")
    print(out, flush=True)
    check("version", f"tree v{version} " in out, out)

    # 没有任何 locale 环境变量时，musl 默认 C.UTF-8，使用 UTF-8 制表符。
    ascii_expected = """t
├── a
│   └── b
│       └── f.txt
├── big.bin
├── deep
│   └── x
│       └── y
│           └── z.c
├── link -> a
├── loop -> .
└── src
    ├── README
    ├── main.c
    └── util.h

9 directories, 6 files
"""
    # 上游 UTF-8 竖线后接两个不换行空格（U+00A0）。
    expected = ascii_expected.replace("│   ", "│   ")
    ascii_expected = (ascii_expected.replace("├──", "|--").replace("└──", "`--")
                      .replace("│", "|"))
    out = text("t")
    check("default output (no locale env, UTF-8 lines)", out == expected, out)
    out = text("t", env={"LANG": "en_US.UTF-8"})
    check("LANG=en_US.UTF-8 same as default", out == expected, out)
    out = text("t", env={"LC_ALL": "C"})
    check("LC_ALL=C uses ASCII lines", out == ascii_expected, out)
    out = text("--charset=ascii", "t")
    check("--charset=ascii", "|-- a" in out and "├" not in out, out)

    out = text("-a", "-L", "1", "--noreport", "t")
    check("-a -L 1 --noreport", out.splitlines() == [
        "t", "├── .hidden", "├── a", "├── big.bin", "├── deep",
        "├── link -> a", "├── loop -> .", "└── src"], out)
    out = text("-d", "t")
    check("-d", "f.txt" not in out and "9 directories\n" in out, out)
    out = text("-fi", "-L", "2", "t/src")
    check("-f -i", out.splitlines()[:4] == ["t/src", "t/src/README", "t/src/main.c", "t/src/util.h"], out)
    out = text("-F", "-L", "1", "t")
    check("-F", "├── a/\n" in out and "├── link -> a/\n" in out, out)
    out = text("--dirsfirst", "-L", "1", "--noreport", "t")
    check("--dirsfirst", out.splitlines()[-1] == "└── big.bin", out)
    out = text("-r", "-L", "1", "--noreport", "t")
    check("-r", out.splitlines()[1] == "├── src", out)
    out = text("-t", "-L", "1", "--noreport", "t")
    check("-t (mtime sort)", out.splitlines()[1] == "├── big.bin", out)
    out = text("--condense", "-d", "t")
    check("--condense", "├── a/b\n" in out and "├── deep/x/y\n" in out, out)
    out = text("--compress=3", "-L", "1", "--noreport", "t")
    check("--compress=3", "├ a\n" in out, out)

    out = text("-P", "*.c", "--prune", "t")
    check("-P --prune", "main.c" in out and "z.c" in out and "util.h" not in out
          and "big.bin" not in out and "\n├── a\n" not in out, out)
    out = text("-I", "deep|src", "t")
    check("-I", "deep" not in out and "src" not in out and "f.txt" in out, out)
    out = text("-P", "readme", "--ignore-case", "t/src")
    check("--ignore-case", "README" in out and "main.c" not in out, out)

    # --gitignore 需要能向上找到 .git 目录。
    (t / ".git").mkdir()
    (t / ".gitignore").write_text("*.bin\ndeep/\n")
    out = text("--gitignore", "t")
    check("--gitignore", "big.bin" not in out and "deep" not in out and "main.c" in out, out)
    shutil.rmtree(t / ".git")
    (t / ".gitignore").unlink()

    out = text("-p", "-u", "-g", "t/src")
    check("-p -u -g names from /etc/passwd /etc/group",
          "[-rw-r--r-- alice    ops     ]  main.c" in out, out)
    check("-u -g unknown id shown as number", "4321     4321    ]  util.h" in out, out)
    out = text("-s", "t", "-P", "big.bin")
    check("-s", "[       2000]  big.bin" in out, out)
    out = text("-h", "t", "-P", "big.bin")
    check("-h", "2.0K]  big.bin" in out, out)
    out = text("--si", "t", "-P", "big.bin")
    check("--si", "2.0k]  big.bin" in out, out)
    out = text("--du", "-s", "t/a")
    check("--du", out.startswith("[") and "f.txt" in out, out)
    out = text("-D", "--timefmt=%Y-%m", "t", "-P", "big.bin", env={"TZ": "UTC0"})
    check("-D --timefmt with TZ", "[2001-01]  big.bin" in out, out)
    out = text("--inodes", "--device", "t", "-L", "1")
    check("--inodes --device", str((t / "big.bin").stat().st_ino) in out, out)

    # -l 对已经访问过的目录（包括 link -> a）同样标记为 recursive，所以链接目标放在树外。
    (root / "work/target").mkdir()
    (root / "work/target/e.txt").touch()
    (root / "work/l").mkdir()
    (root / "work/l/ext").symlink_to("../target")
    (root / "work/l/loop").symlink_to(".")
    out = text("-l", "l")
    check("-l follows link, stops at loop", "ext -> ../target\n│   └── e.txt" in out
          and "loop -> .  [recursive, not followed]" in out, out)

    data = json.loads(run("-J", "-s", "t"))
    top = data[0]
    check("-J JSON", top["type"] == "directory" and top["name"] == "t"
          and data[1] == {"type": "report", "directories": 9, "files": 6}, data)
    names = [e["name"] for e in top["contents"]]
    check("-J contents", names == ["a", "big.bin", "deep", "link", "loop", "src"], names)
    xml = ET.fromstring(run("-X", "t"))
    check("-X XML", xml.tag == "tree" and xml.find("directory").get("name") == "t"
          and xml.find("report/files").text == "6", ET.tostring(xml))
    out = text("-H", ".", "-T", "TEST TITLE", "t")
    check("-H HTML", "<title>TEST TITLE</title>" in out and 'b/f.txt">f.txt</a>' in out, out)
    text("-o", "/tmp/out.txt", "t")
    check("-o output file", (root / "tmp/out.txt").read_text() == expected)

    (root / "work/list.txt").write_text("etc/passwd\netc/group\nusr/bin/tree\n")
    out = text("--fromfile", "list.txt")
    check("--fromfile", "├── etc\n│   ├── group\n│   └── passwd" in out
          and "        └── tree\n" in out, out)

    (t / "src/.info").write_text("main.c\n\tprogram entry\n")
    out = text("--info", "t/src")
    check("--info", "program entry" in out, out)
    (t / "src/.info").unlink()

    # 颜色是写死的 ANSI 序列，不读 terminfo，但上游要求 TERM 变量存在（值不限）。
    colors = {"TERM": "dumb", "LS_COLORS": "di=01;34:ln=01;36"}
    out = text("-C", "t", env=colors)
    check("-C LS_COLORS", "\x1b[01;34ma\x1b[0m" in out, repr(out))
    out = text("-C", "t", env={"LS_COLORS": "di=01;34"})
    check("-C without TERM has no color", "\x1b[" not in out, repr(out))
    force = {**colors, "CLICOLOR_FORCE": "1"}
    out = text("t", env=force)
    check("CLICOLOR_FORCE", "\x1b[01;34m" in out, repr(out))
    out = text("-n", "t", env=force)
    check("-n overrides CLICOLOR_FORCE", "\x1b[" not in out, repr(out))

    raw = run("odd")
    check("UTF-8 filename", "中文.txt".encode() in raw, raw)
    check("default escapes non-printable", b"bad\\377name" in raw and b"nl\\012name" in raw, raw)
    raw = run("-q", "odd")
    check("-q replaces newline", b"nl?name" in raw, raw)
    raw = run("-N", "odd")
    check("-N prints raw bytes", b"bad\xffname" in raw and b"nl\nname" in raw, raw)

    out = text("/nonexistent", code=2)
    check("nonexistent directory", "/nonexistent  [error opening dir]" in out, out)

    # ACL 由 system.posix_acl_access xattr 判断；构建环境的文件系统可能不支持 ACL。
    acl = struct.pack("<I", 2) + b"".join(struct.pack("<HHI", tag, perm, uid) for tag, perm, uid in (
        (0x01, 6, 0xFFFFFFFF), (0x02, 4, 1234), (0x04, 4, 0xFFFFFFFF),
        (0x10, 4, 0xFFFFFFFF), (0x20, 4, 0xFFFFFFFF)))
    try:
        os.setxattr(t / "src/README", "system.posix_acl_access", acl)
    except OSError as e:
        print(f"SKIP: --acl, filesystem rejected ACL xattr ({e})", flush=True)
    else:
        out = text("--acl", "t/src")
        check("--acl", "[-rw-r--r--+]  README" in out and "[-rw-r--r-- ]  main.c" in out, out)

    # 宿主未启用 SELinux 时，部分文件系统仍允许 root 写入 security.selinux xattr。
    label = "system_u:object_r:tmp_t:s0"
    try:
        os.setxattr(t / "src/README", "security.selinux", label.encode() + b"\0")
        label = os.getxattr(t / "src/README", "security.selinux").rstrip(b"\0").decode()
    except OSError as e:
        out = text("--selinux", "t/src")
        check("--selinux without labels runs", "README" in out, out)
        print(f"SKIP: --selinux label output, cannot set label ({e})", flush=True)
    else:
        out = text("--selinux", "t/src")
        check("--selinux", f"[{label}]  README" in out, out)
