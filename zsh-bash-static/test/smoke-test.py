#!/usr/bin/env python3
"""在构建容器内测试；PTY 测试开始前已经移除磁盘 terminfo。"""
import errno
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time


out = Path(sys.argv[1]).resolve()
environment = {
    "PATH": "/usr/bin:/bin",
    "LANG": "C.UTF-8",
    "LC_ALL": "C.UTF-8",
    "TERM": "xterm-256color",
    "PS1": "STATIC> ",
    "PS2": "MORE> ",
    "HISTFILE": "/dev/null",
    "INPUTRC": "/dev/null",
}


def run(shell, script, *, root=None, env=None):
    args = [str(out / shell)] if root is None else [f"/{shell}"]
    args += ["--noprofile", "--norc", "-ec"] if shell == "bash" else ["-fec"]
    result = subprocess.run(
        args + [script], env=env or environment, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60,
        preexec_fn=(lambda: (os.chroot(root), os.chdir("/"))) if root else None,
    )
    if result.returncode:
        raise AssertionError(f"{shell}: exit={result.returncode}\n{script}\n"
                             f"stdout={result.stdout}\nstderr={result.stderr}")
    return result.stdout


bash_core = r"""
declare -A a=([key]=value); [[ ${a[key]} == value ]]
v=中文; [[ ${#v} == 2 ]]
[[ abc123 =~ ^[a-z]+[0-9]+$ ]]
shopt -s extglob; v=aaa; [[ $v == +(a) ]]
mapfile -t rows <<< $'one\ntwo'; [[ ${rows[1]} == two ]]
complete -W 'alpha beta' demo; [[ $(complete -p demo) == *alpha* ]]
[[ $(compgen -W 'alpha beta' -- al) == alpha ]]
help read > /help-output; [[ -s /help-output ]]
printf 'pipeline\n' | { read -r x; [[ $x == pipeline ]]; }
(exit 7) & pid=$!; wait "$pid" && exit 1 || [[ $? == 7 ]]
trap 'v=trapped' USR1; kill -USR1 $$; [[ $v == trapped ]]
printf 'CORE_%s\n' OK
"""

zsh_core = r"""
typeset -A a; a[key]=value; [[ $a[key] == value ]]
v=中文; [[ ${#v} == 2 ]]
setopt extendedglob; [[ aaa == a## ]]
zmodload zsh/regex; [[ abc123 =~ '^[a-z]+[0-9]+$' ]]
zmodload zsh/pcre
pcre_compile '^([a-z]+)([0-9]+)$'; pcre_match abc123
[[ $MATCH == abc123 && $match[1] == abc && $match[2] == 123 ]]
zmodload zsh/db/gdbm
ztie -d db/gdbm -f /test.gdbm db; db[key]=persistent; zuntie db
ztie -d db/gdbm -f /test.gdbm db; [[ $db[key] == persistent ]]; zuntie db
zmodload zsh/mathfunc; (( sqrt(81) == 9 ))
zmodload zsh/datetime; [[ $EPOCHSECONDS -gt 0 ]]
zmodload zsh/stat; zstat -H st /zsh; [[ $st[size] -gt 0 ]]
zmodload zsh/cap; cap > /cap-output
zmodload zsh/system zsh/mapfile zsh/files zsh/zutil zsh/zselect
zmodload zsh/net/tcp zsh/net/socket zsh/zpty zsh/zprof
printf 'pipeline\n' | { read -r x; [[ $x == pipeline ]]; }
(exit 7) & pid=$!; wait $pid && exit 1 || [[ $? == 7 ]]
trap 'v=trapped' USR1; kill -USR1 $$; [[ $v == trapped ]]
print -r -- CORE_OK
"""


def interactive(shell, term, home):
    env = dict(environment, HOME=home, TERM=term, ZDOTDIR=home)
    args = [str(out / shell)]
    args += ["--noprofile", "--norc", "-i"] if shell == "bash" else ["-f", "-i"]
    pid, fd = pty.fork()
    if pid == 0:
        os.execve(args[0], args, env)
    transcript = bytearray()
    pending = bytearray()

    def expect(token):
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            index = pending.find(token)
            if index >= 0:
                del pending[:index + len(token)]
                return
            if select.select([fd], [], [], 0.2)[0]:
                try:
                    data = os.read(fd, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
                if not data:
                    break
                transcript.extend(data)
                pending.extend(data)
        raise AssertionError(f"{shell}/{term}: missing {token!r}\n{transcript!r}")

    try:
        expect(b"STATIC> ")
        os.write(fd, b"unsetopt PROMPT_SP PROMPT_CR 2>/dev/null; PS1='STATIC> '\n"
                 if shell == "zsh" else b"PS1='STATIC> '\n")
        expect(b"STATIC> ")
        # Backspace editing, not just acceptance of a pre-composed command.
        os.write(fd, b"printf 'EDIT_%s\\n' OX\x7fK\n")
        expect(b"EDIT_OK\r\n")
        expect(b"STATIC> ")
        setup = b"demo() { printf 'COMPLETE_%s\\n' \"$1\"; }; "
        setup += (b"complete -W 'static_completion_word' demo\n" if shell == "bash"
                  else b"compctl -k '(static_completion_word)' demo\n")
        os.write(fd, setup)
        expect(b"STATIC> ")
        os.write(fd, b"demo static_compl\t\n")
        expect(b"COMPLETE_static_completion_word\r\n")
        expect(b"STATIC> ")
        os.write(fd, "printf 'UTF8_%s\\n' 中文\n".encode())
        expect("UTF8_中文\r\n".encode())
        expect(b"STATIC> ")
        os.write(fd, "printf 'UTF8EDIT_%s\\n' 中X".encode() + b"\x7f\x7f" + "文\n".encode())
        expect("UTF8EDIT_文\r\n".encode())
        expect(b"STATIC> ")
        if shell == "zsh":
            os.write(fd, b"zmodload zsh/curses; zcurses init && zcurses end && printf 'CURSES_%s\\n' OK\n")
            expect(b"CURSES_OK\r\n")
            expect(b"STATIC> ")
        os.write(fd, b"sleep 30\n")
        time.sleep(0.3)
        os.write(fd, b"\x1a")
        expect(b"STATIC> ")
        os.write(fd, b"jobs; printf 'JOBS_%s\\n' OK\n")
        expect(b"JOBS_OK\r\n")
        if b"Stopped" not in transcript and b"suspended" not in transcript:
            raise AssertionError(f"job was not suspended: {transcript!r}")
        expect(b"STATIC> ")
        os.write(fd, b"fg\n")
        time.sleep(0.3)
        os.write(fd, b"\x03")
        expect(b"STATIC> ")
        os.write(fd, b"exit\n")
        _, status = os.waitpid(pid, 0)
        pid = None
        # The interrupted foreground command can make `exit` return 130.
        if not os.WIFEXITED(status) or os.WEXITSTATUS(status) not in (0, 130):
            raise AssertionError(f"interactive shell exit: {status}")
    finally:
        os.close(fd)
        if pid is not None:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)
    print(f"PASS PTY {shell}/{term}: edit, tab, UTF-8, stop/fg/interrupt", flush=True)


with tempfile.TemporaryDirectory(prefix="shell-static-") as temp:
    root = Path(temp) / "root"
    root.mkdir()
    (root / "etc").mkdir()
    (root / "etc/passwd").write_text("root:x:0:0:root:/:/bash\n")
    (root / "etc/group").write_text("root:x:0:\n")
    for shell, script in (("bash", bash_core), ("zsh", zsh_core)):
        shutil.copy2(out / shell, root / shell)
    for shell, script in (("bash", bash_core), ("zsh", zsh_core)):
        assert "CORE_OK" in run(shell, script, root=str(root))
        print(f"PASS empty-root {shell}: no shared libraries or helper programs", flush=True)

    for shell in ("bash", "zsh"):
        script = r"read -r value < <(printf 'substitution\n'); [[ $value == substitution ]]"
        run(shell, script)
    run("bash", r"""
coproc { printf 'coprocess\n'; read -r reply; }
cp_pid=$COPROC_PID; in_fd=${COPROC[0]}; out_fd=${COPROC[1]}
read -r value <&$in_fd; [[ $value == coprocess ]]
printf 'done\n' >&$out_fd; wait "$cp_pid"
""")
    # Verify every delivered module can actually be activated, not just listed.
    modules = []
    for line in (out / "zsh-config.modules").read_text().splitlines():
        if line.startswith("name=") and "link=static" in line:
            name = line.split()[0].split("=", 1)[1]
            if name != "zsh/main":
                modules.append(name)
    run("zsh", "zmodload " + " ".join(modules))
    print(f"PASS all {len(modules)} statically linked zsh modules", flush=True)
    run("zsh", f"source {out}/init.zsh; (( $+functions[compdef] )); (( $+_comps[git] ))",
        env=dict(environment, HOME=temp, ZDOTDIR=temp))
    print("PASS zsh relocatable compinit and bundled git completion", flush=True)

    # Loopback network tests; no external network or production service involved.
    for shell in ("bash", "zsh"):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            listener.settimeout(30)
            port = listener.getsockname()[1]
            errors = []

            def server():
                try:
                    conn, _ = listener.accept()
                    with conn:
                        conn.sendall(b"network_ok\n")
                except Exception as error:
                    errors.append(error)

            thread = threading.Thread(target=server)
            thread.start()
            try:
                script = (f"exec 3<>/dev/tcp/127.0.0.1/{port}; read -r value <&3; "
                          "[[ $value == network_ok ]]; exec 3>&-" if shell == "bash" else
                          f"zmodload zsh/net/tcp; ztcp 127.0.0.1 {port}; "
                          "fd=$REPLY; read -r value <&$fd; [[ $value == network_ok ]]; ztcp -c $fd")
                run(shell, script)
            finally:
                thread.join(timeout=35)
            if errors:
                raise AssertionError(errors)
        print(f"PASS loopback TCP {shell}", flush=True)

    for term in ("xterm-256color", "screen-256color", "tmux-256color", "linux",
                 "xterm-kitty", "foot", "alacritty"):
        for shell in ("bash", "zsh"):
            interactive(shell, term, temp)

print("All static shell smoke tests passed.", flush=True)
