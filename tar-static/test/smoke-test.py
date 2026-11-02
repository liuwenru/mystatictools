#!/usr/bin/env python3
"""测试 dist 目录中的 GNU tar、bsdtar 和 bsdunzip；需要 root（属主、setuid、ACL）。

bsdtar/bsdunzip 一律用 PATH=/nonexistent 运行，确认压缩/格式都在二进制内完成；
GNU tar 的压缩依赖外部程序，单独测试有/无 PATH 两种情况。
"""
import hashlib
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
TAR = str(out_dir / "tar")
BSDTAR = str(out_dir / "bsdtar")
BSDUNZIP = str(out_dir / "bsdunzip")
tar_version = "1.35"
libarchive_version = "3.8.11"
SYS_PATH = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin"}
NO_PATH = {"PATH": "/nonexistent"}
results = {"pass": 0, "skip": 0}


def check(name, condition, detail=""):
    if not condition:
        raise AssertionError(f"{name}\n{detail}")
    results["pass"] += 1
    print(f"PASS: {name}", flush=True)


def skip(name, reason):
    results["skip"] += 1
    print(f"SKIP: {name}: {reason}", flush=True)


def run(binary, *args, env=None, code=0, cwd=None, stdin=None):
    result = subprocess.run([binary, *map(str, args)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=NO_PATH if env is None else env, cwd=cwd, input=stdin, timeout=120)
    if code is not None and result.returncode != code:
        raise AssertionError(f"{binary} {args}: exit {result.returncode}\n"
                             + result.stdout.decode(errors="replace")
                             + result.stderr.decode(errors="replace"))
    return result.stdout.decode(errors="replace") + result.stderr.decode(errors="replace")


def tool(*args):
    """系统测试工具（setfacl、setfattr 等），失败返回 False。"""
    return subprocess.run(list(map(str, args)), stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0


LONG_DIR = "/".join(["d" * 60] * 3)
UTF8_NAME = "中文目录/数据 文件.txt"


def make_tree(root):
    """固定测试树：属主、权限、mtime、链接、FIFO、长路径、UTF-8 名称和稀疏文件。"""
    root.mkdir()
    (root / "file.txt").write_bytes(b"hello tar\n" * 1000)
    (root / "empty").write_bytes(b"")
    (root / "secret").mkdir(mode=0o750)
    os.chmod(root / "secret", 0o750)
    (root / "secret" / "suid").write_bytes(b"#!/bin/sh\n")
    os.chmod(root / "secret" / "suid", 0o4755)
    (root / "owned").write_bytes(b"owned\n")
    os.chown(root / "owned", 4321, 4321)
    (root / "nobody").write_bytes(b"nobody\n")
    os.chown(root / "nobody", 65534, 65534)
    os.symlink("file.txt", root / "link")
    os.link(root / "file.txt", root / "hard")
    os.mkfifo(root / "fifo")
    (root / LONG_DIR).mkdir(parents=True)
    (root / LONG_DIR / ("f" * 120)).write_bytes(b"long\n")
    (root / UTF8_NAME).parent.mkdir()
    (root / UTF8_NAME).write_bytes("中文内容\n".encode())
    with open(root / "sparse", "wb") as f:
        f.write(b"head")
        f.seek(32 << 20)
        f.write(b"tail")
        f.truncate(64 << 20)
    for path in sorted(root.rglob("*"), reverse=True):
        os.utime(path, (1700000000, 1700000000), follow_symlinks=False)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def compare_tree(src, dst, label, sparse_holes):
    for rel in ("file.txt", "empty", "owned", "nobody", "secret/suid", f"{LONG_DIR}/{'f' * 120}", UTF8_NAME, "sparse"):
        a, b = src / rel, dst / rel
        check(f"{label}: {rel[:40]} content", sha(a) == sha(b))
    st = lambda p: os.lstat(dst / p)
    check(f"{label}: owner 4321 / nobody", (st("owned").st_uid, st("owned").st_gid) == (4321, 4321)
          and st("nobody").st_uid == 65534)
    check(f"{label}: setuid and dir mode", stat.S_IMODE(st("secret/suid").st_mode) == 0o4755
          and stat.S_IMODE(st("secret").st_mode) == 0o750)
    check(f"{label}: mtime", st("file.txt").st_mtime == 1700000000 and st("secret").st_mtime == 1700000000)
    check(f"{label}: symlink", os.readlink(dst / "link") == "file.txt")
    check(f"{label}: hardlink", st("hard").st_ino == st("file.txt").st_ino)
    check(f"{label}: fifo", stat.S_ISFIFO(st("fifo").st_mode))
    if sparse_holes:
        blocks = st("sparse").st_blocks * 512
        check(f"{label}: sparse holes kept ({blocks} bytes allocated)", blocks < (1 << 20))


def magic(path):
    return Path(path).read_bytes()[:6]


work = Path(tempfile.mkdtemp(prefix="tar-static-test-"))
try:
    os.chdir(work)
    src = work / "src"
    make_tree(src)
    holes = os.lstat(src / "sparse").st_blocks * 512 < (1 << 20)
    if not holes:
        skip("sparse hole checks", "filesystem does not keep holes")

    # ---------------- GNU tar ----------------
    out = run(TAR, "--version")
    print(out.splitlines()[0], flush=True)
    check("tar version", f"tar (GNU tar) {tar_version}" in out, out)
    out = run(TAR, "--show-defaults")
    check("tar defaults: -f- and /usr/sbin/rmt", "-f-" in out and "--rmt-command=/usr/sbin/rmt" in out, out)

    for fmt in ("gnu", "posix"):
        archive = work / f"gnu-{fmt}.tar"
        run(TAR, "--sparse", f"--format={fmt}", "-cf", archive, "-C", src, ".")
        dst = work / f"gnu-{fmt}-x"
        dst.mkdir()
        run(TAR, "-xpf", archive, "-C", dst)
        compare_tree(src, dst, f"tar --format={fmt}", holes)
        run(TAR, "-df", archive, "-C", src)
        check(f"tar --format={fmt} -d compare", True)
    out = run(TAR, "-tvf", work / "gnu-posix.tar")
    check("tar -tv user names from /etc/passwd", "nobody/nobody" in out and "4321/4321" in out, out)
    out = run(TAR, "--format=ustar", "-cf", work / "ustar.tar", "-C", src, LONG_DIR, code=2)
    check("tar ustar rejects too long names", "file name is too long" in out, out)
    run(TAR, "--format=ustar", "-cf", work / "ustar.tar", "-C", src, "file.txt")
    check("tar ustar format", Path(work / "ustar.tar").read_bytes()[257:263] == b"ustar\x00")

    # 外部压缩程序：有 PATH 时正常，-a 按扩展名选择；缺少程序时给出明确错误。
    for option, ext, head in (("-z", "gz", b"\x1f\x8b"), ("-j", "bz2", b"BZh"), ("-J", "xz", b"\xfd7zXZ"),
                              ("--zstd", "zst", b"\x28\xb5\x2f\xfd"), ("--lzip", "lz", b"LZIP"),
                              ("--lzop", "lzo", b"\x89LZO")):
        archive = work / f"gnu.tar.{ext}"
        run(TAR, option, "-cf", archive, "-C", src, "file.txt", env=SYS_PATH)
        auto = work / f"auto.tar.{ext}"
        run(TAR, "-acf", auto, "-C", src, "file.txt", env=SYS_PATH)
        out = run(TAR, "-xOf", archive, "file.txt", env=SYS_PATH)
        check(f"tar {option} via external program, -a, auto-detect on extract",
              magic(archive).startswith(head) and magic(auto).startswith(head)
              and out == "hello tar\n" * 1000)
    # tar 1.35 创建时经 /bin/sh -c 启动压缩程序（找不到时 shell 报 not found、子进程 127），
    # 读取时直接按 PATH exec 解压程序。
    out = run(TAR, "-czf", work / "nogzip.tar.gz", "-C", src, "file.txt", code=2)
    check("tar -z create without gzip in PATH reports error", "gzip: not found" in out
          and "Child returned status 127" in out, out)
    out = run(TAR, "-tf", work / "gnu.tar.xz", code=2)
    check("tar reading .xz without xz in PATH reports error", "xz: Cannot exec" in out, out)
    # 默认远程 shell 是编译进去的 /usr/bin/ssh；构建容器没有 ssh 时临时放一个只打印参数的假程序。
    ssh = Path("/usr/bin/ssh")
    fake_ssh = not ssh.exists()
    if fake_ssh:
        ssh.write_text('#!/bin/sh\necho "fake-ssh $*" >&2\nexit 255\n')
        ssh.chmod(0o755)
    try:
        out = run(TAR, "-tf", "backup.example:/tmp/x.tar", code=2)
    finally:
        if fake_ssh:
            ssh.unlink()
    if fake_ssh:
        check("tar host:file runs /usr/bin/ssh host /usr/sbin/rmt",
              "fake-ssh backup.example /usr/sbin/rmt" in out, out)
    else:
        check("tar host:file runs /usr/bin/ssh", "backup.example" in out and "remote shell" not in out, out)

    # 增量备份、过滤、变换和修改归档。
    inc = work / "inc"
    shutil.copytree(src / "secret", inc)
    run(TAR, "-g", work / "snap", "-cf", work / "level0.tar", "-C", work, "inc")
    (inc / "new").write_text("new\n")
    (inc / "suid").unlink()
    run(TAR, "-g", work / "snap", "-cf", work / "level1.tar", "-C", work, "inc")
    names = run(TAR, "-tf", work / "level1.tar").split()
    restore = work / "restore"
    restore.mkdir()
    run(TAR, "-G", "-xf", work / "level0.tar", "-C", restore)
    run(TAR, "-G", "-xf", work / "level1.tar", "-C", restore)
    check("tar -g incremental level1 and -G restore deletions", "inc/new" in names
          and "inc/suid" not in names and sorted(os.listdir(restore / "inc")) == ["new"], names)
    vcs = work / "vcs"
    (vcs / ".git").mkdir(parents=True)
    (vcs / ".git" / "config").write_text("x")
    (vcs / "keep.c").write_text("x")
    (vcs / "drop.o").write_text("x")
    names = run(TAR, "--exclude-vcs", "--exclude=*.o", "--transform=s,^vcs,project,",
                "-cvf", work / "vcs.tar", "-C", work, "vcs").split()
    listed = run(TAR, "-tf", work / "vcs.tar").split()
    check("tar --exclude-vcs --exclude --transform", listed == ["project/", "project/keep.c"], listed)
    (work / "list").write_bytes(b"file.txt\0empty\0")
    run(TAR, "-cf", work / "edit.tar", "-C", src, "--null", "-T", work / "list")
    run(TAR, "-rf", work / "edit.tar", "-C", src, "owned")
    run(TAR, "--delete", "-f", work / "edit.tar", "empty")
    listed = run(TAR, "-tf", work / "edit.tar").split()
    check("tar --null -T, -r append, --delete", listed == ["file.txt", "owned"], listed)
    strip = work / "strip"
    strip.mkdir()
    run(TAR, "-xf", work / "gnu-gnu.tar", "-C", strip, "--strip-components=2", "--wildcards", "./secret/*")
    check("tar --wildcards --strip-components", os.listdir(strip) == ["suid"], os.listdir(strip))
    out = run(TAR, "-xf", work / "gnu-gnu.tar", "--to-command=wc -c", "./file.txt", env=SYS_PATH)
    check("tar --to-command uses /bin/sh", out.strip() == "10000", out)

    # xattr/ACL/SELinux：取决于构建机文件系统，不支持时明确 SKIP。
    meta = work / "meta"
    meta.mkdir()
    (meta / "f").write_text("meta\n")
    if tool("setfattr", "-n", "user.offline", "-v", "ok", meta / "f"):
        run(TAR, "--xattrs", "--xattrs-include=*", "-cf", work / "xattr.tar", "-C", work, "meta")
        dst = work / "xattr-x"
        dst.mkdir()
        run(TAR, "--xattrs", "--xattrs-include=*", "-xf", work / "xattr.tar", "-C", dst)
        check("tar --xattrs user.*", os.getxattr(dst / "meta/f", "user.offline") == b"ok")
        dst = work / "xattr-bsd"
        dst.mkdir()
        run(BSDTAR, "-xpf", work / "xattr.tar", "-C", dst)
        check("bsdtar reads GNU tar xattrs", os.getxattr(dst / "meta/f", "user.offline") == b"ok")
    else:
        skip("xattr", "setfattr user.* not supported here")
    if tool("setfacl", "-m", "u:4321:r", meta / "f"):
        run(TAR, "--acls", "-cf", work / "acl.tar", "-C", work, "meta")
        dst = work / "acl-x"
        dst.mkdir()
        run(TAR, "--acls", "-xf", work / "acl.tar", "-C", dst)
        acl = subprocess.run(["getfacl", "-n", dst / "meta/f"], capture_output=True, text=True).stdout
        check("tar --acls", "user:4321:r--" in acl, acl)
        dst = work / "acl-bsd"
        dst.mkdir()
        run(BSDTAR, "-xpf", work / "acl.tar", "-C", dst)
        acl = subprocess.run(["getfacl", "-n", dst / "meta/f"], capture_output=True, text=True).stdout
        check("bsdtar reads GNU tar ACLs", "user:4321:r--" in acl, acl)
    else:
        skip("ACL", "setfacl not supported here")
    run(TAR, "--selinux", "-cf", work / "selinux.tar", "-C", work, "meta")
    check("tar --selinux accepted without SELinux", True)

    # 翻译：构建阶段已把 tar 源码自带的 zh_CN.mo 装到 /usr/share/locale。
    english = run(TAR, "--bogus", code=64)
    if Path("/usr/share/locale/zh_CN/LC_MESSAGES/tar.mo").exists():
        out = run(TAR, "--bogus", env={**NO_PATH, "LANG": "zh_CN.UTF-8"}, code=64)
        check("tar NLS zh_CN translation", out != english and not out.isascii(), out)
    else:
        skip("tar NLS", "tar.mo not installed")

    # ---------------- bsdtar（全部不依赖 PATH） ----------------
    out = run(BSDTAR, "--version")
    print(out.strip(), flush=True)
    check("bsdtar version", f"bsdtar {libarchive_version} - libarchive {libarchive_version}" in out, out)
    for lib in ("zlib/", "liblzma/", "bz2lib/", "liblz4/", "libzstd/", "liblzo2/", "libxml2/",
                "openssl/", "libacl/"):
        check(f"bsdtar built with {lib.rstrip('/')}", lib in out, out)

    archive = work / "bsd.tar"
    run(BSDTAR, "--format=pax", "-cf", archive, "-C", src, ".")
    dst = work / "bsd-x"
    dst.mkdir()
    run(BSDTAR, "-xpf", archive, "-C", dst)
    compare_tree(src, dst, "bsdtar pax", holes)
    dst = work / "bsd-from-gnu"
    dst.mkdir()
    run(BSDTAR, "-xpf", work / "gnu-gnu.tar", "-C", dst)
    compare_tree(src, dst, "bsdtar reads GNU format", holes)
    dst = work / "gnu-from-bsd"
    dst.mkdir()
    # bsdtar 不保证同一目录的成员连续；GNU tar 默认离开目录就恢复其 mtime，需延迟恢复。
    run(TAR, "--delay-directory-restore", "-xpf", archive, "-C", dst)
    compare_tree(src, dst, "GNU tar --delay-directory-restore reads bsdtar pax", holes)
    out = run(BSDTAR, "-tvf", archive)
    check("bsdtar -tv user names from /etc/passwd", "nobody" in out and "4321" in out, out)

    for option, ext, head in (("-z", "gz", b"\x1f\x8b"), ("-j", "bz2", b"BZh"), ("-J", "xz", b"\xfd7zXZ"),
                              ("--lzma", "lzma", b"\x5d\x00\x00"), ("--zstd", "zst", b"\x28\xb5\x2f\xfd"),
                              ("--lz4", "lz4", b"\x04\x22\x4d\x18"), ("--lzop", "lzo", b"\x89LZO"),
                              ("--lzip", "lz", b"LZIP"), ("-Z", "Z", b"\x1f\x9d")):
        archive = work / f"bsd.tar.{ext}"
        run(BSDTAR, option, "-cf", archive, "-C", src, "file.txt")
        auto = work / f"bsd-auto.tar.{ext}"
        if ext != "Z":
            run(BSDTAR, "-acf", auto, "-C", src, "file.txt")
        out = run(BSDTAR, "-xOf", archive, "file.txt")
        check(f"bsdtar {option} built-in (no PATH), auto-detect on extract",
              magic(archive).startswith(head) and (ext == "Z" or magic(auto).startswith(head))
              and out == "hello tar\n" * 1000)
        if ext in ("gz", "bz2", "xz", "zst", "lz", "lzo"):
            out = run(TAR, "-xOf", archive, "file.txt", env=SYS_PATH)
            check(f"GNU tar + system {ext} reads bsdtar output", out == "hello tar\n" * 1000)
    out = run(BSDTAR, "-xOf", work / "gnu.tar.zst", "file.txt")
    check("bsdtar reads GNU tar .zst without zstd program", out == "hello tar\n" * 1000)

    for fmt, ext, head in (("zip", "zip", b"PK\x03\x04"), ("7zip", "7z", b"7z\xbc\xaf\x27\x1c"),
                           ("newc", "cpio", b"070701"), ("iso9660", "iso", None), ("xar", "xar", b"xar!"),
                           ("ar", "a", b"!<arch>\n"), ("shar", "shar", b"#!/bin/sh")):
        archive = work / f"fmt.{ext}"
        members = ["file.txt"] if fmt == "ar" else ["file.txt", UTF8_NAME]
        run(BSDTAR, f"--format={fmt}", "-cf", archive, "-C", src, *members)
        if head:
            check(f"bsdtar --format={fmt} header", magic(archive).startswith(head[:6]), magic(archive))
        if fmt == "shar":
            continue  # shar 只写不读
        if fmt == "iso9660":
            check("bsdtar --format=iso9660 header", Path(archive).read_bytes()[32769:32774] == b"CD001")
        dst = work / f"fmt-{ext}"
        dst.mkdir()
        run(BSDTAR, "-xf", archive, "-C", dst)
        check(f"bsdtar {fmt} round trip", sha(dst / "file.txt") == sha(src / "file.txt")
              and (fmt == "ar" or sha(dst / UTF8_NAME) == sha(src / UTF8_NAME)))
    out = subprocess.run(["cpio", "-it"], stdin=open(work / "fmt.cpio", "rb"), capture_output=True).stdout
    check("system cpio reads bsdtar newc", b"file.txt" in out, out)

    run(BSDTAR, "--format=zip", "--options=zip:encryption=aes256", "--passphrase", "s3cret",
        "-cf", work / "aes.zip", "-C", src, "file.txt")
    out = run(BSDTAR, "--passphrase", "s3cret", "-xOf", work / "aes.zip")
    check("bsdtar zip AES-256 encryption via OpenSSL", out == "hello tar\n" * 1000)
    out = run(BSDTAR, "--passphrase", "wrong", "-xOf", work / "aes.zip", code=1)
    check("bsdtar zip wrong passphrase rejected", "assphrase" in out or "ncorrect" in out, out)
    out = run(BSDTAR, "--format=mtree", "--options=mtree:sha256", "-cf", "-", "-C", src, "file.txt")
    check("bsdtar mtree sha256 digest via OpenSSL", f"sha256digest={sha(src / 'file.txt')}" in out, out)

    if tool("setfattr", "-n", "user.bsd", "-v", "ok", meta / "f"):
        run(BSDTAR, "-cf", work / "bsd-meta.tar", "-C", work, "meta")
        dst = work / "bsd-meta"
        dst.mkdir()
        run(BSDTAR, "-xpf", work / "bsd-meta.tar", "-C", dst)
        check("bsdtar xattrs", os.getxattr(dst / "meta/f", "user.bsd") == b"ok")
        acl = subprocess.run(["getfacl", "-n", dst / "meta/f"], capture_output=True, text=True).stdout
        if "user:4321" in subprocess.run(["getfacl", "-n", meta / "f"], capture_output=True, text=True).stdout:
            check("bsdtar ACLs", "user:4321:r--" in acl, acl)
        dst = work / "gnu-meta"
        dst.mkdir()
        run(TAR, "--xattrs", "--xattrs-include=*", "--acls", "-xf", work / "bsd-meta.tar", "-C", dst)
        check("GNU tar reads bsdtar xattrs", os.getxattr(dst / "meta/f", "user.bsd") == b"ok")
    else:
        skip("bsdtar xattr/ACL", "setfattr user.* not supported here")

    flag = work / "flag"
    flag.write_text("x")
    if tool("chattr", "+d", flag):
        run(BSDTAR, "-cf", work / "fflags.tar", "-C", work, "flag")
        out = run(BSDTAR, "--format=mtree", "-cf", "-", "@" + str(work / "fflags.tar"))
        check("bsdtar --fflags reads chattr flags", "nodump" in out, out)
    else:
        skip("bsdtar fflags", "chattr not supported on this filesystem")

    # ---------------- bsdunzip（全部不依赖 PATH） ----------------
    out = run(BSDUNZIP, "--version")
    check("bsdunzip version", f"bsdunzip {libarchive_version} - libarchive {libarchive_version}" in out, out)
    zsrc = work / "zsrc"
    zsrc.mkdir()
    (zsrc / "data.txt").write_bytes(b"0123456789abcdef\n" * 4096)
    (zsrc / "run.sh").write_text("#!/bin/sh\n")
    os.chmod(zsrc / "run.sh", 0o750)
    os.symlink("data.txt", zsrc / "link")
    os.utime(zsrc / "data.txt", (1700000000, 1700000000))
    subprocess.run(["zip", "-q", "-y", "-r", work / "info.zip", "."], cwd=zsrc, check=True)
    dst = work / "bunzip"
    run(BSDUNZIP, "-q", work / "info.zip", "-d", dst)
    st = lambda p: os.lstat(dst / p)
    check("bsdunzip extracts Info-ZIP zip: content, mode, symlink, mtime",
          sha(dst / "data.txt") == sha(zsrc / "data.txt") and stat.S_IMODE(st("run.sh").st_mode) == 0o750
          and os.readlink(dst / "link") == "data.txt" and st("data.txt").st_mtime == 1700000000)
    out = run(BSDUNZIP, "-l", work / "info.zip")
    check("bsdunzip -l", "Length" in out and "data.txt" in out and "run.sh" in out, out)
    out = run(BSDUNZIP, "-t", work / "info.zip")
    check("bsdunzip -t", "No errors detected" in out, out)
    out = run(BSDUNZIP, "-p", work / "info.zip", "data.txt")
    check("bsdunzip -p", out == "0123456789abcdef\n" * 4096)
    dst = work / "bunzip-j"
    run(BSDUNZIP, "-q", "-j", work / "info.zip", "-x", "link", "-d", dst)
    check("bsdunzip -j -x", sorted(os.listdir(dst)) == ["data.txt", "run.sh"], os.listdir(dst))
    (dst / "data.txt").write_text("old")
    run(BSDUNZIP, "-q", "-o", work / "info.zip", "data.txt", "-d", dst)
    check("bsdunzip -o overwrite", sha(dst / "data.txt") == sha(zsrc / "data.txt"))
    subprocess.run(["zip", "-q", "-P", "s3cret", work / "zcrypto.zip", "data.txt"], cwd=zsrc, check=True)
    for archive, label in ((work / "zcrypto.zip", "ZipCrypto"), (work / "aes.zip", "AES-256")):
        out = run(BSDUNZIP, "-P", "s3cret", "-p", archive, "data.txt" if label == "ZipCrypto" else "file.txt")
        check(f"bsdunzip {label} password", out.startswith("0123456789abcdef\n" if label == "ZipCrypto"
                                                          else "hello tar\n"), out[:80])
    for method, label in ((zipfile.ZIP_BZIP2, "bzip2"), (zipfile.ZIP_LZMA, "lzma")):
        archive = work / f"method-{label}.zip"
        with zipfile.ZipFile(archive, "w", method) as z:
            z.writestr("d.txt", "data\n" * 100)
        out = run(BSDUNZIP, "-p", archive)
        check(f"bsdunzip zip method {label}", out == "data\n" * 100)

    def raw_zip(path, entries):
        """文件名按给定字节写入、不设 UTF-8 标志，模拟 Windows 本地编码的 zip。"""
        local, central, offsets = b"", b"", []
        for name, data in entries:
            offsets.append(len(local))
            local += struct.pack("<4sHHHHHIIIHH", b"PK\x03\x04", 20, 0, 0, 0, 0x5b00, zlib.crc32(data),
                                 len(data), len(data), len(name), 0) + name + data
        for (name, data), offset in zip(entries, offsets):
            central += struct.pack("<4sHHHHHHIIIHHHHHII", b"PK\x01\x02", 20, 20, 0, 0, 0, 0x5b00,
                                   zlib.crc32(data), len(data), len(data), len(name), 0, 0, 0, 0, 0,
                                   offset) + name
        Path(path).write_bytes(local + central + struct.pack("<4sHHHHIIH", b"PK\x05\x06", 0, 0, len(entries),
                                                             len(entries), len(central), len(local), 0))

    cn = "中文目录/报表.txt"
    raw_zip(work / "gbk.zip", [(cn.encode("gbk"), b"g\n")])
    for charset in ("GBK", "GB18030"):
        dst = work / f"bunzip-{charset}"
        run(BSDUNZIP, "-q", "-I", charset, work / "gbk.zip", "-d", dst)
        check(f"bsdunzip -I {charset} Chinese name", (dst / cn).read_bytes() == b"g\n")
    out = run(BSDUNZIP, "-q", "-I", "CP936", work / "gbk.zip", "-d", work / "bunzip-cp936", code=1)
    check("bsdunzip -I CP936 unsupported by musl iconv (use GBK)", "CP936" in out, out)
    raw_zip(work / "traverse.zip", [(b"../../evil.txt", b"e\n"), (b"/abs.txt", b"a\n")])
    dst = work / "bunzip-trav"
    out = run(BSDUNZIP, work / "traverse.zip", "-d", dst)
    check("bsdunzip skips ../ and absolute entries", "insecure" in out and not (work / "evil.txt").exists()
          and not Path("/abs.txt").exists(), out)
finally:
    os.chdir("/")
    shutil.rmtree(work, ignore_errors=True)

print(f"ALL PASS: {results['pass']} checks, {results['skip']} skipped", flush=True)
