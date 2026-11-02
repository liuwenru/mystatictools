#!/usr/bin/env python3
"""测试 dist 目录中的静态 rsync；需要 root（属主、设备文件、ACL、守护进程 chroot）。

rsync 本身一律用 PATH=/nonexistent 运行，确认不依赖外部程序。远程 shell 用本脚本生成的
fake-rsh 模拟 ssh（把远程命令交给 /bin/sh 执行）。与旧版本互通用 Alpine 自带的 /usr/bin/rsync。
"""
import os
from pathlib import Path
import re
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
import time

out_dir = Path(sys.argv[1]).resolve()
RSYNC = str(out_dir / "rsync")
OLD_RSYNC = sys.argv[2] if len(sys.argv) > 2 else "/usr/bin/rsync"
rsync_version = "3.5.1"
ENV = {"PATH": "/nonexistent", "LANG": "C.UTF-8"}
results = {"pass": 0, "skip": 0}
work = Path(tempfile.mkdtemp(prefix="rsync-smoke."))


def check(name, condition, detail=""):
    if not condition:
        raise AssertionError(f"{name}\n{detail}")
    results["pass"] += 1
    print(f"PASS: {name}", flush=True)


def skip(name, reason):
    results["skip"] += 1
    print(f"SKIP: {name}: {reason}", flush=True)


def run(*args, binary=None, env=None, code=0, stdin=None):
    cmd = [binary or RSYNC, *map(str, args)]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, input=stdin,
                            env=ENV if env is None else env, timeout=120)
    text = result.stdout.decode(errors="replace") + result.stderr.decode(errors="replace")
    if code is not None and result.returncode != code:
        raise AssertionError(f"{cmd}: exit {result.returncode}, expected {code}\n{text}")
    return text


def tool(*args):
    """系统测试工具（setfacl、getfacl 等），返回 stdout，失败抛异常。"""
    return subprocess.run(list(map(str, args)), check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE).stdout.decode()


def fresh(name):
    path = work / name
    if path.exists():
        shutil.rmtree(path)
    return path


def stat_value(text, label):
    match = re.search(rf"^{re.escape(label)}: ([\d,]+)", text, re.M)
    return int(match.group(1).replace(",", "")) if match else None


# 模拟 ssh：rsync 调用 "rsh [-l user] host 命令..."，ssh 把命令拼成一行交给远端 shell。
FAKE_RSH = work / "fake-rsh"
FAKE_RSH.write_text('#!/bin/sh\nwhile [ "$1" = -l ]; do shift 2; done\nshift\nexec /bin/sh -c "$*"\n')
FAKE_RSH.chmod(0o755)
RSH = ["-e", str(FAKE_RSH), f"--rsync-path={RSYNC}"]

LONG_DIR = "/".join(["d" * 60] * 4)
UTF8_NAME = "中文目录/数据 文件.txt"
ACL_OK = shutil.which("setfacl") is not None


def make_tree(root):
    """属主、权限、mtime、软/硬链接、FIFO、设备、稀疏文件、长路径、UTF-8 名称、xattr、ACL。"""
    root.mkdir(parents=True)
    (root / "file.txt").write_bytes(b"hello rsync\n" * 2000)
    (root / "empty").write_bytes(b"")
    (root / "secret").mkdir(mode=0o750)
    os.chmod(root / "secret", 0o750)
    (root / "secret" / "suid").write_bytes(b"#!/bin/sh\n")
    os.chmod(root / "secret" / "suid", 0o4755)
    (root / "owned").write_bytes(b"owned\n")
    os.chown(root / "owned", 4321, 4322)
    os.symlink("file.txt", root / "link")
    os.symlink("/nonexistent/target", root / "dangling")
    os.link(root / "file.txt", root / "hard")
    os.mkfifo(root / "fifo")
    os.mknod(root / "null", 0o666 | stat.S_IFCHR, os.makedev(1, 3))
    with open(root / "sparse", "wb") as f:
        f.seek(8 * 1024 * 1024)
        f.write(b"end\n")
    (root / LONG_DIR).mkdir(parents=True)
    (root / LONG_DIR / ("f" * 200)).write_bytes(b"long\n")
    (root / UTF8_NAME).parent.mkdir()
    (root / UTF8_NAME).write_bytes(b"utf8\n")
    os.setxattr(root / "file.txt", "user.comment", b"rsync xattr")
    os.setxattr(root / "secret", "user.dir", b"dir xattr")
    if ACL_OK:
        tool("setfacl", "-m", "u:4321:rwx,g:4322:r-x", root / "owned")
        tool("setfacl", "-d", "-m", "u:4321:rwx", root / "secret")
    os.utime(root / "file.txt", ns=(1_600_000_000_123_456_789, 1_600_000_000_123_456_789))
    # 软链接、FIFO、设备文件的 mtime 若与目标创建时间落在同一秒，上游 rsync（glibc 版同样）可能不设置纳秒部分，
    # 因此统一设为过去的时间，测试保留能力而不是这个时间窗口。
    for name in ["link", "dangling", "fifo", "null"]:
        os.utime(root / name, ns=(1_500_000_000_000_000_001, 1_500_000_000_000_000_001), follow_symlinks=False)


def snapshot(root):
    """记录每个条目的元数据，硬链接用组号表示，便于比较两个目录树。"""
    data, inodes = {}, {}
    for dirpath, dirnames, filenames in os.walk(root):
        for name in dirnames + filenames:
            path = Path(dirpath) / name
            rel = str(path.relative_to(root))
            st = os.lstat(path)
            item = {"mode": st.st_mode, "uid": st.st_uid, "gid": st.st_gid}
            if not stat.S_ISDIR(st.st_mode):
                item["mtime"] = st.st_mtime_ns
            if stat.S_ISREG(st.st_mode):
                item["size"] = st.st_size
                item["data"] = path.read_bytes()
                if st.st_nlink > 1:
                    item["hardlink"] = inodes.setdefault(st.st_ino, len(inodes))
            if stat.S_ISLNK(st.st_mode):
                item["target"] = os.readlink(path)
            if stat.S_ISCHR(st.st_mode) or stat.S_ISBLK(st.st_mode):
                item["rdev"] = st.st_rdev
            if not stat.S_ISLNK(st.st_mode):
                item["xattr"] = sorted((k, os.getxattr(path, k)) for k in os.listxattr(path)
                                       if k.startswith("user."))
                if ACL_OK and (stat.S_ISREG(st.st_mode) or stat.S_ISDIR(st.st_mode)):
                    item["acl"] = tool("getfacl", "-cpn", path)
            data[rel] = item
    return data


def compare(name, src, dst):
    a, b = snapshot(src), snapshot(dst)
    diff = [k for k in sorted(set(a) | set(b)) if a.get(k) != b.get(k)]
    check(name, not diff, "\n".join(f"{k}: {a.get(k)!r:.300} != {b.get(k)!r:.300}" for k in diff[:5]))


# --- 1. 版本、编译能力 ------------------------------------------------------------
version = run("--version")
check("版本 3.5.1、协议 33", f"rsync  version {rsync_version}  protocol version 33" in version, version)
caps = version.split("Capabilities:")[1].split("Optimizations:")[0]
for cap in ["64-bit files", "socketpairs", "symlinks", "symtimes", "hardlinks", "hardlink-specials",
            "hardlink-symlinks", "IPv6", "atimes", "batchfiles", "inplace", "append", "ACLs", "xattrs",
            "iconv", "prealloc", "ACL-at"]:
    check(f"能力 {cap}", re.search(rf"(^|[ ,]){re.escape(cap)}(,|$)", caps, re.M)
          and not re.search(rf"no {re.escape(cap)}(,|$)", caps, re.M), caps)
for algo in ["xxh128", "xxh3", "xxh64", "md5", "md4", "sha1"]:
    check(f"校验算法 {algo}", re.search(rf"Checksum list:\s*\n\s*.*\b{algo}\b", version), version)
for algo in ["zstd", "lz4", "zlibx", "zlib"]:
    check(f"压缩算法 {algo}", re.search(rf"Compress list:\s*\n\s*.*\b{algo}\b", version), version)
for algo in ["sha512", "sha256", "sha1", "md5", "md4"]:
    check(f"守护进程认证摘要 {algo}", re.search(rf"Daemon auth list:\s*\n\s*.*\b{algo}\b", version), version)
check("openssl-crypto 已启用", "openssl-crypto" in version and "no openssl-crypto" not in version, version)

# --- 2. 本地完整复制：-aHAXS 保留全部元数据 ----------------------------------------
src = fresh("src")
make_tree(src)
dst = fresh("dst")
run("-aHAXS", "--numeric-ids", f"{src}/", dst)
compare("本地 -aHAXS --numeric-ids 元数据一致", src, dst)
check("-S 稀疏文件保留空洞", os.stat(dst / "sparse").st_blocks * 512 < 1024 * 1024,
      str(os.stat(dst / "sparse").st_blocks))
check("硬链接保持同一 inode", os.stat(dst / "file.txt").st_ino == os.stat(dst / "hard").st_ino)
check("纳秒 mtime", os.stat(dst / "file.txt").st_mtime_ns == 1_600_000_000_123_456_789)
out = run("-aHAXSn", "--numeric-ids", "-i", f"{src}/", dst)
check("再次同步无差异", out.strip() == "", out)

# --- 3. 远程 shell：增量传输与各校验算法 ------------------------------------------
big = fresh("big")
big.mkdir()
payload = bytearray(os.urandom(4 * 1024 * 1024))
(big / "data.bin").write_bytes(payload)
for algo in ["xxh128", "xxh3", "xxh64", "md5", "md4", "sha1"]:
    dst = fresh(f"delta-{algo}")
    run("-a", *RSH, f"{big}/", f"host:{dst}/")
    changed = bytearray(payload)
    changed[2_000_000:2_000_100] = b"x" * 100
    (big / "data.bin").write_bytes(changed)
    os.utime(big / "data.bin", (1_700_000_000, 1_700_000_000))
    out = run("-a", "--stats", f"--checksum-choice={algo}", *RSH, f"{big}/", f"host:{dst}/")
    literal, matched = stat_value(out, "Literal data"), stat_value(out, "Matched data")
    check(f"增量传输 {algo}：只传改动的块", literal is not None and literal < 200_000
          and matched > 3_000_000 and (dst / "data.bin").read_bytes() == changed, out)
    (big / "data.bin").write_bytes(payload)
    out = run("-ac", "-i", f"--checksum-choice={algo}", *RSH, f"{big}/", f"host:{dst}/")
    check(f"-c 整文件校验 {algo} 发现差异", re.search(r"^<fc", out, re.M), out)
    check(f"-c {algo} 同步后内容一致", (dst / "data.bin").read_bytes() == bytes(payload))

# --- 4. 压缩算法 ------------------------------------------------------------------
text = fresh("text")
text.mkdir()
(text / "log.txt").write_bytes(b"2026-11-02 INFO rsync static build compress test line\n" * 100_000)
sizes = {}
for algo in ["none", "zstd", "lz4", "zlibx", "zlib"]:
    dst = fresh(f"cpres-{algo}")
    args = ["-a", "--stats"] + ([] if algo == "none" else ["-z", f"--compress-choice={algo}"])
    out = run(*args, *RSH, f"{text}/", f"host:{dst}/")
    sizes[algo] = stat_value(out, "Total bytes sent")
    check(f"压缩 {algo} 内容一致", (dst / "log.txt").read_bytes() == (text / "log.txt").read_bytes())
for algo in ["zstd", "lz4", "zlibx", "zlib"]:
    check(f"压缩 {algo} 实际减少传输量", sizes[algo] < sizes["none"] // 5, str(sizes))
out = run("-a", "-z", "--compress-choice=zstd", "--compress-level=19", *RSH, f"{text}/",
          f"host:{fresh('cpres-zstd19')}/")
check("zstd --compress-level=19", (work / "cpres-zstd19" / "log.txt").exists())

# --- 5. 远程 shell 下保留元数据 ---------------------------------------------------
dst = fresh("remote-meta")
run("-aHAXS", "--numeric-ids", *RSH, f"{src}/", f"host:{dst}/")
compare("远程 shell -aHAXS 推送元数据一致", src, dst)
dst2 = fresh("remote-meta-pull")
run("-aHAXS", "--numeric-ids", *RSH, f"host:{src}/", dst2)
compare("远程 shell -aHAXS 拉取元数据一致", src, dst2)

# --- 6. 常用选项 ------------------------------------------------------------------
dst = fresh("opts")
run("-a", f"{src}/", dst)
(dst / "extra").write_bytes(b"extra\n")
run("-a", "--delete", f"{src}/", dst)
check("--delete 删除多余文件", not (dst / "extra").exists())
(src / "file.txt").write_bytes(b"changed\n")
run("-a", "--backup", "--suffix=.bak", f"{src}/", dst)
check("--backup --suffix", (dst / "file.txt.bak").read_bytes() == b"hello rsync\n" * 2000)
link = fresh("link-dest")
run("-a", f"--link-dest={dst}", f"{src}/", link)
check("--link-dest 未变化的文件做硬链接", os.stat(link / "owned").st_ino == os.stat(dst / "owned").st_ino)
filt = fresh("filter")
run("-a", "--exclude=*.txt", "--include=*/", f"{src}/", filt)
check("--exclude", not (filt / "file.txt").exists() and (filt / "owned").exists())
(work / "list").write_text("owned\nsecret/suid\n")
ff = fresh("files-from")
run("-a", f"--files-from={work / 'list'}", f"{src}/", ff)
check("--files-from", sorted(str(p.relative_to(ff)) for p in ff.rglob("*") if p.is_file())
      == ["owned", "secret/suid"])
listing = run("-r", "--list-only", f"{src}/")
check("--list-only", "file.txt" in listing and re.search(r"^-rwsr-xr-x .* secret/suid$", listing, re.M), listing)
dry = run("-ain", f"{src}/", fresh("dry"))
check("--dry-run 不写入", not (work / "dry").exists() and ">f+++++++++ file.txt" in dry, dry)
inplace = fresh("inplace")
inplace.mkdir()
(inplace / "data.bin").write_bytes(bytes(payload))
os.utime(inplace / "data.bin", (1_600_000_000, 1_600_000_000))  # 避免大小、mtime 秒数相同被快速检查跳过
inode = os.stat(inplace / "data.bin").st_ino
(big / "data.bin").write_bytes(changed)
run("-a", "--inplace", f"{big}/", inplace)
check("--inplace 原地更新", os.stat(inplace / "data.bin").st_ino == inode
      and (inplace / "data.bin").read_bytes() == changed)
append = fresh("append")
append.mkdir()
(append / "data.bin").write_bytes(bytes(changed[:1_000_000]))
run("-a", "--append-verify", f"{big}/", append)
check("--append-verify", (append / "data.bin").read_bytes() == changed)
rm_src = fresh("remove-src")
rm_src.mkdir()
(rm_src / "a").write_bytes(b"a")
run("-a", "--remove-source-files", f"{rm_src}/", fresh("remove-dst"))
check("--remove-source-files", not (rm_src / "a").exists() and (work / "remove-dst" / "a").exists())
chown = fresh("chown")
run("-a", "--chown=nobody:nobody", f"{src}/file.txt", f"{chown}/")
st = os.stat(chown / "file.txt")
check("--chown 按 /etc/passwd 解析名称", (st.st_uid, st.st_gid) == (65534, 65534), str(st))
um = fresh("usermap")
run("-a", "--usermap=4321:nobody", "--groupmap=4322:nobody", f"{src}/owned", f"{um}/")
st = os.stat(um / "owned")
check("--usermap/--groupmap", (st.st_uid, st.st_gid) == (65534, 65534), str(st))
progress = run("-a", "--info=progress2,stats3", f"{src}/", fresh("progress"))
check("--info=progress2,stats3", "to-chk=0/" in progress and "Number of files" in progress, progress)

# --- 7. 批处理模式 ----------------------------------------------------------------
base1, base2 = fresh("batch1"), fresh("batch2")
run("-a", f"{src}/", base1)
run("-a", f"{src}/", base2)
(src / "file.txt").write_bytes(b"batch change\n" * 500)
run("-a", f"--write-batch={work / 'batch.bin'}", f"{src}/", base1)
run("-a", f"--read-batch={work / 'batch.bin'}", base2)
check("--write-batch/--read-batch", (base2 / "file.txt").read_bytes() == b"batch change\n" * 500)

# --- 8. 守护进程 ------------------------------------------------------------------
def free_port(family=socket.AF_INET, addr="127.0.0.1"):
    with socket.socket(family, socket.SOCK_STREAM) as s:
        s.bind((addr, 0))
        return s.getsockname()[1]


def start_daemon(binary, conf, port, address="127.0.0.1"):
    proc = subprocess.Popen([binary, "--daemon", "--no-detach", f"--config={conf}", f"--port={port}",
                             f"--address={address}"], env=ENV, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    family = socket.AF_INET6 if ":" in address else socket.AF_INET
    for _ in range(100):
        try:
            with socket.create_connection((address, port), timeout=0.2):
                return proc
        except OSError:
            if proc.poll() is not None:
                raise AssertionError(proc.stdout.read().decode(errors="replace"))
            time.sleep(0.05)
    proc.kill()
    raise AssertionError(f"daemon on {address}:{port} did not start")


def stop(proc):
    proc.terminate()
    proc.wait(timeout=10)


pub, upload = fresh("d-pub"), fresh("d-upload")
run("-a", f"{src}/", pub)
upload.mkdir()
upload.chmod(0o1777)  # [upload] 以 nobody 写入
secrets = work / "rsyncd.secrets"
secrets.write_text("alice:s3cret\n")
secrets.chmod(0o600)
pwfile, badpw = work / "pw", work / "badpw"
pwfile.write_text("s3cret\n")
badpw.write_text("wrong\n")
pwfile.chmod(0o600)
badpw.chmod(0o600)
conf = work / "rsyncd.conf"
conf.write_text(f"""pid file = {work}/rsyncd.pid
log file = {work}/rsyncd.log
uid = root
gid = root
[pub]
    path = {pub}
    comment = public read-only
    read only = yes
[upload]
    path = {upload}
    read only = no
    use chroot = yes
    uid = nobody
    gid = nobody
    auth users = alice
    secrets file = {secrets}
[denied]
    path = {pub}
    hosts deny = nope.nonexistent.invalid
""")
port = free_port()
daemon = start_daemon(RSYNC, conf, port)
try:
    url = f"rsync://127.0.0.1:{port}"
    mods = run(f"{url}/")
    check("守护进程列出模块", "pub" in mods and "public read-only" in mods and "upload" in mods, mods)
    got = fresh("d-got")
    run("-a", f"{url}/pub/", got)
    check("守护进程拉取", (got / "file.txt").read_bytes() == (src / "file.txt").read_bytes())
    out = run("-a", f"{src}/", f"{url}/pub/", code=None)
    check("只读模块拒绝上传", "read only" in out, out)
    run("-rt", f"--password-file={pwfile}", f"{src}/owned", f"rsync://alice@127.0.0.1:{port}/upload/")
    st = os.stat(upload / "owned")
    check("认证上传，chroot 下以 nobody 写入", (st.st_uid, st.st_gid) == (65534, 65534), str(st))
    out = run("-rt", f"--password-file={badpw}", f"{src}/owned", f"rsync://alice@127.0.0.1:{port}/upload/",
              code=5)
    check("错误密码被拒绝（退出码 5）", "auth failed" in out, out)
    out = run(f"{url}/denied/", code=None)
    check("hosts deny 无法解析的主机名时拒绝（断网环境）", "access denied" in out.lower()
          or "@ERROR" in out, out)
finally:
    stop(daemon)

try:
    port6 = free_port(socket.AF_INET6, "::1")
except OSError as e:
    skip("IPv6 守护进程", f"::1 不可用：{e}")
else:
    daemon = start_daemon(RSYNC, conf, port6, "::1")
    try:
        mods = run(f"rsync://[::1]:{port6}/")
        check("IPv6 [::1] 守护进程", "pub" in mods, mods)
    finally:
        stop(daemon)

# --- 9. 与旧版本 rsync 互通 -------------------------------------------------------
old_version = run("--version", binary=OLD_RSYNC).splitlines()[0]
print(f"旧版本：{old_version}", flush=True)
for direction in ["push", "pull"]:
    dst = fresh(f"old-rsh-{direction}")
    rsh = ["-e", str(FAKE_RSH), f"--rsync-path={OLD_RSYNC}"]
    if direction == "push":
        run("-aHAXz", "--numeric-ids", *rsh, f"{src}/", f"host:{dst}/")
    else:
        run("-aHAXz", "--numeric-ids", *rsh, f"host:{src}/", dst)
    compare(f"新客户端 {direction} ↔ 旧版本远端（远程 shell，-z）", src, dst)
dst = fresh("old-client")
run("-aHAXz", "--numeric-ids", "-e", str(FAKE_RSH), f"--rsync-path={RSYNC}", f"{src}/", f"host:{dst}/",
    binary=OLD_RSYNC)
compare("旧版本客户端 → 新版本远端（远程 shell，-z）", src, dst)
port = free_port()
daemon = start_daemon(RSYNC, conf, port)
try:
    got = fresh("old-from-new-daemon")
    run("-az", f"rsync://127.0.0.1:{port}/pub/", got, binary=OLD_RSYNC)
    check("旧版本客户端 ← 新版本守护进程", (got / "owned").read_bytes() == b"owned\n")
    run("-rt", f"--password-file={pwfile}", f"{src}/file.txt", f"rsync://alice@127.0.0.1:{port}/upload/",
        binary=OLD_RSYNC)
    check("旧版本客户端认证上传到新版本守护进程", (upload / "file.txt").exists())
finally:
    stop(daemon)
port = free_port()
daemon = start_daemon(OLD_RSYNC, conf, port)
try:
    got = fresh("new-from-old-daemon")
    run("-az", f"rsync://127.0.0.1:{port}/pub/", got)
    check("新版本客户端 ← 旧版本守护进程", (got / "owned").read_bytes() == b"owned\n")
    run("-rt", f"--password-file={pwfile}", f"{src}/empty", f"rsync://alice@127.0.0.1:{port}/upload/")
    check("新版本客户端认证上传到旧版本守护进程", (upload / "empty").exists())
finally:
    stop(daemon)

# --- 10. --iconv 文件名编码转换（GNU libiconv） -----------------------------------
cn = fresh("iconv-src")
cn.mkdir()
(cn / "中文.txt").write_bytes(b"cn\n")
(cn / "日本.txt").write_bytes(b"jp\n")
for charset, pyname, name in [("GBK", "gbk", "中文.txt"), ("GB18030", "gb18030", "中文.txt"),
                              ("BIG5", "big5", "中文.txt"), ("SHIFT_JIS", "shift_jis", "日本.txt")]:
    dst = fresh(f"iconv-{charset}")
    run("-a", f"--iconv=UTF-8,{charset}", *RSH, f"{cn}/{name}", f"host:{dst}/")
    expected = name.encode(pyname)
    check(f"--iconv UTF-8 → {charset}", os.listdir(os.fsencode(dst)) == [expected],
          repr(os.listdir(os.fsencode(dst))))
    back = fresh(f"iconv-{charset}-back")
    run("-a", f"--iconv={charset},UTF-8", *RSH, f"{dst}/", f"host:{back}/")
    check(f"--iconv {charset} → UTF-8", os.listdir(back) == [name], repr(os.listdir(os.fsencode(back))))

# --- 11. IDN 域名（不联网：经 -e 连接守护进程时，转换后的主机名作为参数传给远程 shell） ---------
# 注意 RSYNC_CONNECT_PROG 的 %H 在 IDN 转换之前替换，不能用来观察（glibc 版同样）。
REC_RSH = work / "record-rsh"
REC_RSH.write_text('#!/bin/sh\necho "RSH-ARGS: $*" >&2\nexit 1\n')  # stdout 是 rsync 协议通道
REC_RSH.chmod(0o755)
for label, env in [("LANG=C.UTF-8", ENV), ("未设置 locale", {"PATH": "/nonexistent"})]:
    out = run("-e", REC_RSH, "rsync://例子.测试/mod/", env=env, code=None)
    check(f"IDN 主机名转为 Punycode（{label}）", "RSH-ARGS: xn--fsqu00a.xn--0zwm56d " in out, out)

# --- 12. 不读取宿主 openssl.cnf ---------------------------------------------------
# 只激活 null provider 的配置：OpenSSL 若读取它，默认 provider 不加载，只能由 EVP 提供的 sha1 不可用；
# md5/md4 有 rsync 内置实现，不受影响。
NULL_CNF = ("openssl_conf = init\n[init]\nproviders = prov\n[prov]\nnull = null_sect\n"
            "[null_sect]\nactivate = 1\n")
bad = work / "null-provider.cnf"
bad.write_text(NULL_CNF)
out = run("-ac", "--checksum-choice=sha1", *RSH, f"{big}/", f"host:{fresh('ossl-env')}/",
          env=dict(ENV, OPENSSL_CONF=str(bad)), code=None)
check("OPENSSL_CONF 环境变量仍然生效（此配置下 sha1 不可用，传输失败）",
      "sha1" in out and not (work / "ossl-env" / "data.bin").exists(), out)
cnf = Path("/etc/ssl/openssl.cnf")
saved = cnf.read_bytes() if cnf.exists() else None
try:
    cnf.parent.mkdir(parents=True, exist_ok=True)
    cnf.write_text(NULL_CNF)
    for algo in ["sha1", "md5", "md4"]:
        dst = fresh(f"ossl-{algo}")
        run("-ac", f"--checksum-choice={algo}", *RSH, f"{big}/", f"host:{dst}/")
        check(f"不读取 /etc/ssl/openssl.cnf：{algo} 正常", (dst / "data.bin").read_bytes() == changed)
finally:
    if saved is None:
        cnf.unlink()
    else:
        cnf.write_bytes(saved)

# --- 13. 缺少 ssh 时的报错 --------------------------------------------------------
out = run("-a", f"{src}/", "host:/tmp/x", code=None)
check("没有 ssh 时报错退出", "ssh" in out and ("No such file" in out or "not found" in out), out)

shutil.rmtree(work)
print(f"smoke-test: {results['pass']} passed, {results['skip']} skipped", flush=True)
