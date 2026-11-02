#!/usr/bin/env python3
"""测试 dist 目录中的 unzip/zipinfo/funzip；需要 root（-X 还原属主）。

Ubuntu autopkgtest 已覆盖常规解压、列表、zipinfo、funzip、unzipsfx、大文件；
这里补充文件名编码、属主/权限/链接、安全修复和无环境变量运行。
"""
import os
from pathlib import Path
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import zipfile
import zlib

out_dir = Path(sys.argv[1]).resolve()
UNZIP = str(out_dir / "unzip")
ZIPINFO = str(out_dir / "zipinfo")
FUNZIP = str(out_dir / "funzip")
NO_PATH = {"PATH": "/nonexistent"}
count = 0


def check(name, condition, detail=""):
    global count
    if not condition:
        raise AssertionError(f"{name}\n{detail}")
    count += 1
    print(f"PASS: {name}", flush=True)


def run(binary, *args, env=None, code=0, cwd=None, stdin=None):
    result = subprocess.run([binary, *map(str, args)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=NO_PATH if env is None else env, cwd=cwd, input=stdin, timeout=60)
    if code is not None and result.returncode != code:
        raise AssertionError(f"{binary} {args}: exit {result.returncode}\n"
                             + result.stdout.decode(errors="replace")
                             + result.stderr.decode(errors="replace"))
    return result.stdout.decode(errors="replace") + result.stderr.decode(errors="replace")


def raw_zip(path, entries, overlap=False):
    """手工写 zip：文件名按给定字节存放，不设 UTF-8 标志（模拟 Windows 本地编码压缩）。"""
    local, central = b"", b""
    offsets = []
    for name, data in entries:
        crc = zlib.crc32(data)
        offsets.append(len(local))
        local += struct.pack("<4sHHHHHIIIHH", b"PK\x03\x04", 20, 0, 0, 0, 0x5b00,
                             crc, len(data), len(data), len(name), 0) + name + data
    for i, (name, data) in enumerate(entries):
        offset = offsets[0] if overlap else offsets[i]
        crc = zlib.crc32(entries[0][1] if overlap else data)
        size = len(entries[0][1]) if overlap else len(data)
        central += struct.pack("<4sHHHHHHIIIHHHHHII", b"PK\x01\x02", 20, 20, 0, 0, 0, 0x5b00,
                               crc, size, size, len(name), 0, 0, 0, 0, 0, offset) + name
    eocd = struct.pack("<4sHHHHIIH", b"PK\x05\x06", 0, 0, len(entries), len(entries),
                       len(central), len(local), 0)
    Path(path).write_bytes(local + central + eocd)


def extract(archive, *opts, env=None, code=0):
    dst = Path(tempfile.mkdtemp(dir=work))
    out = run(UNZIP, "-q", *opts, archive, "-d", dst, env=env, code=code)
    return dst, out


def names(dst):
    return sorted(str(p.relative_to(dst)) for p in dst.rglob("*") if p.is_file())


work = Path(tempfile.mkdtemp(prefix="unzip-static-test-"))
try:
    os.chdir(work)
    out = run(UNZIP, "-v")
    check("unzip -v without PATH/LANG", "UnZip 6.00 of 20 April 2009, by Debian" in out
          and "USE_BZIP2" in out and "ZIP64_SUPPORT" in out and "UNICODE_SUPPORT" in out, out)

    # ---------------- 文件名编码 ----------------
    cn = "中文目录/报表 2026.txt"
    raw_zip(work / "gbk.zip", [(cn.encode("gbk"), b"gbk\n")])
    dst, _ = extract(work / "gbk.zip")
    check("GBK name without LANG keeps raw bytes (no guess)", names(dst) != [cn], names(dst))
    for env, label in (({**NO_PATH, "LANG": "zh_CN.UTF-8"}, "LANG=zh_CN.UTF-8 auto CP936"),
                       ({**NO_PATH, "LC_ALL": "zh_CN.UTF-8"}, "LC_ALL=zh_CN.UTF-8 auto CP936")):
        dst, _ = extract(work / "gbk.zip", env=env)
        check(f"GBK name, {label}", names(dst) == [cn], names(dst))
    for charset in ("CP936", "cp936", "GBK", "GB18030"):
        dst, _ = extract(work / "gbk.zip", "-O", charset)
        check(f"GBK name, -O {charset}", names(dst) == [cn] and (dst / cn).read_bytes() == b"gbk\n", names(dst))
    out = run(UNZIP, "-O", "CP936", "-l", work / "gbk.zip")
    check("unzip -O CP936 -l shows Chinese", cn in out, out)
    out = run(ZIPINFO, "-O", "CP936", work / "gbk.zip")
    check("zipinfo -O CP936 shows Chinese", cn in out, out)
    big5 = "繁體中文.txt"
    raw_zip(work / "big5.zip", [(big5.encode("big5"), b"b\n")])
    dst, _ = extract(work / "big5.zip", env={**NO_PATH, "LANG": "zh_TW.UTF-8"})
    check("Big5 name, LANG=zh_TW.UTF-8 auto CP950", names(dst) == [big5], names(dst))
    jp = "日本語ファイル.txt"
    raw_zip(work / "sjis.zip", [(jp.encode("cp932"), b"j\n")])
    dst, _ = extract(work / "sjis.zip", env={**NO_PATH, "LANG": "ja_JP.UTF-8"})
    check("Shift_JIS name, LANG=ja_JP.UTF-8 auto CP932", names(dst) == [jp], names(dst))
    with zipfile.ZipFile(work / "utf8.zip", "w") as z:
        z.writestr(cn, "utf8\n")  # Python 对非 ASCII 名称设置 UTF-8 标志
    for env in (NO_PATH, {**NO_PATH, "LANG": "zh_CN.UTF-8"}):
        dst, _ = extract(work / "utf8.zip", env=env)
        check(f"UTF-8 flagged name not re-encoded (LANG={env.get('LANG', '')})", names(dst) == [cn], names(dst))

    # ---------------- 压缩方法、密码 ----------------
    src = work / "src"
    src.mkdir()
    (src / "data.txt").write_bytes(b"0123456789abcdef\n" * 4096)
    # Alpine 的 zip 未启用 bzip2，用 Python 写 method 12。
    with zipfile.ZipFile(work / "bz.zip", "w", zipfile.ZIP_BZIP2) as z:
        z.write(src / "data.txt", "data.txt")
    out = run(UNZIP, "-v", work / "bz.zip")
    dst, _ = extract(work / "bz.zip")
    check("bzip2 method (static libbz2)", "BZip2" in out
          and (dst / "data.txt").read_bytes() == (src / "data.txt").read_bytes(), out)
    run(UNZIP, "-tq", work / "bz.zip")
    check("unzip -t", True)
    # Zip64 头：不写 4 GiB 实际数据，强制用 Zip64 扩展字段记录大小和偏移。
    with zipfile.ZipFile(work / "zip64.zip", "w", zipfile.ZIP_DEFLATED) as z:
        with z.open(zipfile.ZipInfo("big.txt"), "w", force_zip64=True) as f:
            f.write((src / "data.txt").read_bytes())
    out = run(UNZIP, "-v", work / "zip64.zip")
    dst, _ = extract(work / "zip64.zip")
    check("Zip64 extra field", (dst / "big.txt").read_bytes() == (src / "data.txt").read_bytes(), out)
    subprocess.run(["zip", "-q", "-P", "s3cret", work / "enc.zip", "data.txt"], cwd=src, check=True)
    dst, _ = extract(work / "enc.zip", "-P", "s3cret")
    check("ZipCrypto -P correct password", (dst / "data.txt").exists())
    out = run(UNZIP, "-P", "wrong", "-t", work / "enc.zip", code=82)
    check("ZipCrypto wrong password exit 82", "incorrect password" in out, out)

    # ---------------- 权限、属主、链接、时间 ----------------
    (src / "run.sh").write_text("#!/bin/sh\n")
    os.chmod(src / "run.sh", 0o750)
    (src / "owned").write_text("o\n")
    os.chown(src / "owned", 4321, 4321)
    os.symlink("data.txt", src / "link")
    os.utime(src / "data.txt", (1700000000, 1700000000))
    # zip 默认写入 UT/ux 扩展字段（时间、uid/gid）；zip 的 -X 是去掉它们，不能加。
    subprocess.run(["zip", "-q", "-y", "-r", work / "unix.zip", "."], cwd=src, check=True)
    dst, _ = extract(work / "unix.zip", "-X")
    st = lambda p: os.lstat(dst / p)
    check("mode 0750 restored", stat.S_IMODE(st("run.sh").st_mode) == 0o750)
    check("symlink restored", os.readlink(dst / "link") == "data.txt")
    check("mtime restored", st("data.txt").st_mtime == 1700000000, st("data.txt").st_mtime)
    check("-X restores uid/gid 4321", (st("owned").st_uid, st("owned").st_gid) == (4321, 4321))
    out = run(UNZIP, "-l", work / "unix.zip")
    check("unzip -l classic format", out.splitlines()[1].split() == ["Length", "Date", "Time", "Name"]
          and "data.txt" in out, out)
    out = run(ZIPINFO, work / "unix.zip")
    check("zipinfo via symlink name", "lrwxrwxrwx" in out and "-rwxr-x---" in out, out)
    out = run(UNZIP, "-Z", "-1", work / "unix.zip")
    check("unzip -Z -1", "data.txt" in out.split(), out)
    out = run(UNZIP, "-p", work / "unix.zip", "data.txt")
    check("unzip -p to stdout", out == "0123456789abcdef\n" * 4096)
    dst = Path(tempfile.mkdtemp(dir=work))
    run(UNZIP, "-q", "-j", work / "unix.zip", "-x", "link", "owned", "-d", dst)
    check("unzip -j -x", sorted(os.listdir(dst)) == ["data.txt", "run.sh"], os.listdir(dst))
    out = run(UNZIP, work / "unix.zip", "nosuch", code=11)
    check("unmatched name exit 11", "filename not matched" in out, out)
    # funzip 上游只支持 deflate/stored，bzip2 明确报错。
    with zipfile.ZipFile(work / "deflate.zip", "w", zipfile.ZIP_DEFLATED) as z:
        z.write(src / "data.txt", "data.txt")
    out = run(FUNZIP, stdin=(work / "deflate.zip").read_bytes())
    check("funzip from stdin (deflate)", out == "0123456789abcdef\n" * 4096)
    out = run(FUNZIP, stdin=(work / "bz.zip").read_bytes(), code=3)
    check("funzip rejects bzip2 entry (upstream limit)", "not deflated or stored" in out, out)

    # ---------------- 安全修复 ----------------
    raw_zip(work / "bomb.zip", [(b"a.txt", b"x" * 100), (b"b.txt", b"x" * 100)], overlap=True)
    _, out = extract(work / "bomb.zip", code=12)
    check("CVE-2019-13232 overlapped entries rejected", "overlapped components" in out, out)
    raw_zip(work / "traverse.zip", [(b"../../evil.txt", b"evil\n"), (b"/abs.txt", b"abs\n")])
    dst, out = extract(work / "traverse.zip", code=None)
    check("../ and absolute paths stay inside -d", sorted(os.listdir(dst)) == ["abs.txt", "evil.txt"]
          and not (work / "evil.txt").exists() and not Path("/abs.txt").exists(), out)

    # 随包手册页能被渲染，且包含 Ubuntu 补丁加入的 -O/-I 说明。
    if shutil.which("mandoc"):
        for page in ("unzip.1", "zipinfo.1", "funzip.1"):
            text = subprocess.run(["mandoc", "-Tascii", out_dir / page], capture_output=True, text=True,
                                  check=True).stdout
            check(f"man page {page} renders", len(text) > 1000, text[:200])
    source = (out_dir / "unzip.1").read_text(errors="replace")
    check("unzip.1 documents -O/-I charset (Ubuntu patch)", "\\-O" in source and "\\-I" in source
          and "charset" in source.lower())
finally:
    os.chdir("/")
    shutil.rmtree(work, ignore_errors=True)

print(f"ALL PASS: {count} checks", flush=True)
