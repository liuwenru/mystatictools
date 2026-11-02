#!/usr/bin/env python3
"""测试 dist 目录中的 pstree 和 procs；需要 root（切换子进程 UID）。

pstree/procs 需要真实 /proc，构建容器内无法在 chroot 中挂载，所以直接以空环境变量运行，
Dockerfile 在运行前删除容器内的 terminfo 数据库。
"""
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time

out_dir = Path(sys.argv[1]).resolve()
pstree = str(out_dir / "pstree")
procs = str(out_dir / "procs")
psmisc_version = "23.7"
procs_version = "0.14.12"
sleep = shutil.which("sleep")


def check(name, condition, detail=""):
    if not condition:
        raise AssertionError(f"{name}\n{detail}")
    print(f"PASS: {name}", flush=True)


def run(binary, *args, env=None, code=0):
    result = subprocess.run([binary, *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env={} if env is None else env, timeout=30)
    if result.returncode != code:
        raise AssertionError(f"{binary} {args}: exit {result.returncode}\n"
                             + result.stdout.decode(errors="replace")
                             + result.stderr.decode(errors="replace"))
    return result.stdout.decode(errors="replace") + result.stderr.decode(errors="replace")


def run_pty(binary, *args, env, rows=50, cols=200, send=None, timeout=10):
    """在伪终端中运行，返回输出和退出状态。"""
    pid, fd = pty.fork()
    if pid == 0:
        os.execve(binary, [binary, *args], env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    out = b""
    start = time.time()
    sent = False
    while time.time() - start < timeout:
        if send and not sent and time.time() - start > 2:
            os.write(fd, send)
            sent = True
        ready, _, _ = select.select([fd], [], [], 0.1)
        if ready:
            try:
                data = os.read(fd, 65536)
            except OSError:
                break
            if not data:
                break
            out += data
    try:
        done, status = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        done, status = pid, 0
    if done == 0:
        os.kill(pid, 9)
        os.waitpid(pid, 0)
        raise AssertionError(f"{binary} {args} did not exit\n" + out.decode(errors="replace"))
    os.close(fd)
    return out.decode(errors="replace"), os.waitstatus_to_exitcode(status)


# 固定的进程树：tparent 下有 2 个 root sleep、nobody 和 4321 各一个 sleep、2 个 worker 线程。
FIXTURE = r"""
import os, sys, threading
sleep = sys.argv[1]
os.makedirs("/tmp", exist_ok=True)
with open("/proc/self/comm", "w") as f:
    f.write("tparent")
for uid in (0, 0, 65534, 4321):
    if os.fork() == 0:
        os.setgid(uid)
        os.setuid(uid)
        os.execv(sleep, [sleep, "300"])
stop = threading.Event()
named = threading.Barrier(3)
def worker():
    with open(f"/proc/self/task/{threading.get_native_id()}/comm", "w") as f:
        f.write("worker")
    named.wait()
    stop.wait()
for _ in range(2):
    threading.Thread(target=worker, daemon=True).start()
named.wait()
sys.stdout.write("ready\n")
sys.stdout.flush()
sys.stdin.read()
"""

fixture = subprocess.Popen([sys.executable, "-c", FIXTURE, sleep],
                           stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
try:
    assert fixture.stdout.readline() == "ready\n"
    time.sleep(0.3)
    parent = str(fixture.pid)
    children = sorted(int(p) for p in
                      Path(f"/proc/{parent}/task/{parent}/children").read_text().split())
    assert len(children) == 4, children

    # ---------------- pstree ----------------
    out = run(pstree, "-V")
    print(out, flush=True)
    check("pstree version", f"pstree (PSmisc) {psmisc_version}" in out, out)

    out = run(pstree, parent)
    check("pstree compact output (pipe uses ASCII)",
          out == "tparent-+-4*[sleep]\n        `-2*[{tparent}]\n", out)
    out = run(pstree, "-t", parent)
    check("-t full thread names", "`-2*[{worker}]" in out, out)
    out = run(pstree, "-c", parent)
    check("-c no compaction", out.count("sleep") == 4 and out.count("{tparent}") == 2, out)
    out = run(pstree, "-T", parent)
    check("-T hides threads", out == "tparent---4*[sleep]\n", out)
    out = run(pstree, "-p", "-T", "-n", parent)
    expected = f"tparent({parent})-+-sleep({children[0]})\n"
    check("-p -n pids sorted", out.startswith(expected)
          and all(f"sleep({c})" in out for c in children), out)
    out = run(pstree, "-a", "-T", parent)
    check("-a arguments", "sleep 300" in out and out.startswith("tparent -c"), out)
    out = run(pstree, "-u", "-T", parent)
    check("-u uid transitions from /etc/passwd", "sleep(nobody)" in out
          and "sleep(4321)" in out and "2*[sleep]" in out, out)
    out = run(pstree, "-g", "-T", parent)
    check("-g pgids", f"tparent({os.getpgid(fixture.pid)})" in out, out)
    out = run(pstree, "-s", "-T", str(children[0]))
    check("-s show parents", "tparent---sleep" in out and out.index("tparent") > 0, out)
    out = run(pstree, "-U", parent)
    check("-U UTF-8 lines", "tparent─┬─4*[sleep]" in out and "└─2*[{tparent}]" in out, out)
    out = run(pstree, "-G", parent)
    check("-G VT100 lines", "\x1b(0" in out and "\x1b(B" in out, repr(out))
    out = run(pstree, "-C", "age", "-T", parent)
    check("-C age color", "\x1b[" in out, repr(out))
    out = run(pstree, "-Z", "-T", parent)
    check("-Z security context (/proc/PID/attr/current)", out.startswith("tparent(`"), out)
    out = run(pstree, "-S", "-T", parent)
    check("-S namespaces runs", out.startswith("tparent"), out)
    out = run(pstree, "-N", "pid", "-T", parent)
    check("-N pid runs", "tparent" in out, out)
    out = run(pstree, "-N", "bogus", code=1)
    check("-N invalid rejected", "Usage" in out, out)
    out = run(pstree, "nobody")
    check("user argument", out.strip() == "sleep", out)
    out = run(pstree)
    check("full tree", "tparent" in out and out.count("\n") > 1, out)
    out = run(pstree, "-T", parent, env={"COLUMNS": "12"})
    check("COLUMNS truncation", max(map(len, out.splitlines())) <= 12 and "+" in out, out)
    out = run(pstree, "-l", "-T", parent, env={"COLUMNS": "12"})
    check("-l long lines", "tparent---4*[sleep]" in out, out)

    # 终端：无 locale 环境变量时 musl 默认 UTF-8；LC_ALL=C 时走 setupterm 判断后用 ASCII。
    out, code = run_pty(pstree, "-T", parent, env={"TERM": "xterm"})
    check("tty default UTF-8 lines", code == 0 and "tparent───4*[sleep]" in out, repr(out))
    out, code = run_pty(pstree, "-T", parent, env={"TERM": "xterm", "LANG": "zh_CN.UTF-8"})
    check("tty LANG=zh_CN.UTF-8 UTF-8 lines", code == 0 and "tparent───4*[sleep]" in out, repr(out))
    out, code = run_pty(pstree, "-T", parent, env={"TERM": "xterm", "LC_ALL": "C"})
    check("tty LC_ALL=C ASCII lines", code == 0 and "tparent---4*[sleep]" in out, repr(out))

    # 翻译从 /usr/share/locale/*/LC_MESSAGES/psmisc.mo 读取；构建容器装了 Alpine 的 psmisc-lang。
    english = run(pstree, "-H", parent, parent, code=1)
    if Path("/usr/share/locale/zh_CN/LC_MESSAGES/psmisc.mo").exists():
        out = run(pstree, "-H", parent, parent, env={"LANG": "zh_CN.UTF-8"}, code=1)
        check("NLS zh_CN translation", out != english and not out.isascii(), out)
    else:
        print("SKIP: NLS translation, psmisc.mo not installed", flush=True)

    # 高亮依赖 terminfo；构建容器中的数据库已删除，xterm/vt100 来自内嵌 fallback。
    for term in ("xterm", "xterm-256color", "vt100", "linux", "screen", "tmux-256color"):
        if Path("/usr/share/terminfo").exists():
            raise AssertionError("system terminfo still present, fallback not tested")
        out = run(pstree, "-H", parent, "-T", parent, env={"TERM": term})
        check(f"-H highlight via embedded {term}", "\x1b[1mtparent" in out, repr(out))
    out = run(pstree, "-H", parent, parent, env={"TERM": "nosuchterm"}, code=1)
    check("-H unknown TERM reported", "Can't get terminal capabilities" in out, out)
    out = run(pstree, "-H", parent, parent, code=1)
    check("-H without TERM reported", "TERM is not set" in out, out)

    # 目标机自带的 terminfo 数据库仍然优先使用：编译一个 bold 为反显的自定义条目。
    with tempfile.TemporaryDirectory(prefix="pstree-terminfo-") as terminfo:
        src = Path(terminfo) / "custom.src"
        src.write_text("pstreetest|pstree smoke test,\n\tbold=\\E[7m, sgr0=\\E[m,\n")
        subprocess.run(["tic", "-o", terminfo, src], check=True)
        out = run(pstree, "-H", parent, "-T", parent,
                  env={"TERM": "pstreetest", "TERMINFO": terminfo})
        check("-H uses on-disk terminfo (TERMINFO)", "\x1b[7mtparent" in out, repr(out))

    # ---------------- procs ----------------
    out = run(procs, "--version")
    print(out, flush=True)
    check("procs version", f'procs "{procs_version} ' in out, out)
    base = ["--pager", "disable", "--color", "disable"]
    # procs 按命令行（不是 comm 名称）搜索，fixture 父进程显示为 python3 -c ...。
    out = run(procs, *base, "sleep 300")
    check("procs text search", all(str(c) in out for c in children), out)
    out = run(procs, *base, "--regex", "sle+p [0-9]{3}")
    check("procs regex search", all(str(c) in out for c in children), out)
    rows = json.loads(run(procs, "--json", "--pager", "disable", "--or", *map(str, children)))
    users = sorted(r["User"] for r in rows)
    check("procs --json and user names", sorted(r["PID"] for r in rows) == children
          and users == ["4321", "nobody", "root", "root"], rows)
    out = run(procs, *base, "--tree", parent)
    check("procs --tree with threads", f" {parent} " in out and "sleep 300" in out
          and out.count("│ worker\n") == 2, out)
    out = run(procs, *base, "--thread", "worker")
    check("procs --thread", out.count("worker") >= 2, out)
    out = run(procs, *base, "--sortd", "cpu", "--only", "pid", "--or", *map(str, children))
    check("procs --sortd --only", sorted(int(x) for x in out.split() if x.isdigit()) == children, out)
    out = run(procs, "--gen-config")
    check("procs --gen-config", "[[columns]]" in out, out[:200])
    out = run(procs, "--gen-completion-out", "bash")
    check("procs bash completion", "_procs()" in out, out[:200])

    # 终端：--theme 固定主题，避免自动探测终端背景色时等待终端应答。
    env = {"TERM": "xterm", "PATH": "/nonexistent"}
    out, code = run_pty(procs, "--theme", "dark", "--pager", "always", parent, env=env)
    check("procs tty without less/more prints directly", code == 0 and parent in out, out)
    out, code = run_pty(procs, "--theme", "dark", "--watch", parent, env=env, send=b"q")
    check("procs --watch quits on q", code == 0 and parent in out, out)
finally:
    # 只结束本测试创建的子进程。
    try:
        pids = Path(f"/proc/{fixture.pid}/task/{fixture.pid}/children").read_text().split()
    except FileNotFoundError:
        pids = []
    for pid in pids:
        try:
            os.kill(int(pid), 9)
        except ProcessLookupError:
            pass
    fixture.stdin.close()
    fixture.wait(timeout=10)
