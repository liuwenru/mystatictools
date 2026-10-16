#!/usr/bin/env python3
"""Build-container smoke test; requires Python, /bin/sh and a usable /dev/pts."""

import errno
import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time


binary = os.path.abspath(sys.argv[1])
environment = dict(os.environ, LC_ALL="C.UTF-8", SHELL="/bin/sh")

with tempfile.TemporaryDirectory(prefix="tmux-smoke-") as temporary:
    socket = os.path.join(temporary, "socket")
    environment.update(HOME=temporary, TERMINFO=temporary, TERMINFO_DIRS=temporary)
    command = [binary, "-S", socket, "-f", "/dev/null"]

    def run(*arguments):
        return subprocess.check_output(
            command + list(arguments), env=environment, text=True, timeout=20
        ).strip()

    # Each terminal must actually attach through a PTY, not just start a server.
    for terminal in ("xterm-256color", "screen-256color", "tmux-256color", "linux", "xterm-kitty", "foot", "alacritty"):
        environment["TERM"] = terminal
        pid, descriptor = pty.fork()
        if pid == 0:
            os.execve(binary, command + ["new-session", "-s", "smoke"], environment)
        fcntl.ioctl(descriptor, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
        output = bytearray()
        try:
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                if select.select([descriptor], [], [], 0.1)[0]:
                    try:
                        chunk = os.read(descriptor, 65536)
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
                    if not chunk:
                        break
                    output.extend(chunk)
                if os.path.exists(socket):
                    try:
                        if run("list-clients", "-F", "#{client_termname}") == terminal:
                            break
                    except subprocess.CalledProcessError:
                        pass
            else:
                raise AssertionError(f"attach timed out: {terminal}")

            assert run("list-clients", "-F", "#{client_termname}") == terminal, output.decode(errors="replace")
            run("split-window", "-h")
            assert len(run("list-panes").splitlines()) == 2
            run("send-keys", "-t", "smoke:0.0", "printf 'STATIC_%s\\n' 'TMUX_中文_OK'", "Enter")
            deadline = time.monotonic() + 10
            while "STATIC_TMUX_中文_OK" not in [
                line.strip() for line in run("capture-pane", "-p", "-t", "smoke:0.0").splitlines()
            ]:
                if time.monotonic() >= deadline:
                    raise AssertionError("pane output missing")
                time.sleep(0.1)
            assert run("show-options", "-gv", "default-terminal") == "screen-256color"
            run("detach-client")
            assert run("has-session", "-t", "smoke") == ""
            print(f"OK: {terminal}: attach, split, Unicode, detach", flush=True)
        finally:
            subprocess.run(command + ["kill-server"], env=environment, timeout=20, check=False)
            # A successful detach should let the client exit; cap cleanup time.
            deadline = time.monotonic() + 5
            while os.waitpid(pid, os.WNOHANG) == (0, 0):
                if time.monotonic() >= deadline:
                    os.kill(pid, signal.SIGKILL)
                    os.waitpid(pid, 0)
                    break
                time.sleep(0.05)
            os.close(descriptor)
