#!/usr/bin/env python3
"""Run the delivered binary in an otherwise empty chroot, using a real PTY."""

import fcntl
import os
import pty
import select
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time

binary = os.path.abspath(sys.argv[1])
IAC = b"\xff"


def until(read, token, timeout=8):
    data = b""
    end = time.monotonic() + timeout
    while token not in data and time.monotonic() < end:
        data += read()
    assert token in data, (token, data)
    return data


with tempfile.TemporaryDirectory(prefix="telnet-test-") as root:
    shutil.copy2(binary, root + "/telnet")

    def enter():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)
        os.chroot(root)
        os.chdir("/")

    def spawn(args, term="xterm-256color"):
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 37, 101, 0, 0))
        env = dict(PATH="", HOME="/", TERM=term, LC_ALL="C", SHISHI_HOME="/missing")
        proc = subprocess.Popen(["/telnet", *args], stdin=slave, stdout=slave, stderr=slave, env=env, preexec_fn=enter)
        os.close(slave)

        def read():
            if not select.select([master], [], [], 0.1)[0]:
                return b""
            try:
                return os.read(master, 65536)
            except OSError:
                return b""

        return proc, master, read

    def stop(proc, master):
        if proc.poll() is None:
            proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        os.close(master)

    def command(text, expected):
        proc, fd, read = spawn([])
        try:
            until(read, b"telnet> ")
            os.write(fd, text + b"\n")
            until(read, expected)
            os.write(fd, b"quit\n")
            assert proc.wait(timeout=5) == 0
        finally:
            stop(proc, fd)

    for text, expected in [
        (b"help", b"close"),
        (b"auth status", b"KERBEROS_V5"),
        (b"encrypt type ?", b"DES_CFB64"),
        (b"send do 256", b"bad value"),
        (b"help help", b"print help information"),
    ]:
        command(text, expected)
        print("PASS command:", text.decode())

    proc, fd, read = spawn([])
    try:
        until(read, b"telnet> ")
        os.write(fd, b"open\n")
        until(read, b"(to) ")
        os.write(fd, b"\n")
        until(read, b"telnet> ")
        os.write(fd, b"quit\n")
        assert proc.wait(timeout=5) == 0
    finally:
        stop(proc, fd)
    print("PASS interactive open prompt")

    def session(family, term="xterm-256color", binary_mode=False, port=0):
        host = "127.0.0.1" if family == socket.AF_INET else "::1"
        with socket.socket(family) as listener:
            listener.settimeout(8)
            listener.bind((host, port))
            listener.listen()
            number = listener.getsockname()[1]
            args = ["-c", "-K"]
            if binary_mode:
                args += ["-8"]
            args += ["--", host]
            if port != 23:
                args += ["-" + str(number)]  # force initial Telnet negotiation on custom port
            proc, fd, read = spawn(args, term)
            try:
                try:
                    conn, _ = listener.accept()
                except TimeoutError:
                    raise AssertionError(("connect timeout", proc.poll(), read())) from None
                with conn:
                    conn.settimeout(0.1)

                    wire = bytearray()

                    def netread():
                        try:
                            chunk = conn.recv(65536)
                            wire.extend(chunk)
                            return chunk
                        except socket.timeout:
                            return b""

                    until(read, b"Connected to")
                    # TTYPE, window size, echo/SGA, and binary option negotiation.
                    conn.sendall(IAC + b"\xfd\x18" + IAC + b"\xfd\x1f" + IAC + b"\xfb\x01" + IAC + b"\xfb\x03")
                    until(netread, IAC + b"\xfa\x1f\x00\x65\x00\x25" + IAC + b"\xf0")
                    conn.sendall(IAC + b"\xfa\x18\x01" + IAC + b"\xf0")
                    until(netread, IAC + b"\xfa\x18\x00" + term.upper().encode() + IAC + b"\xf0")
                    assert IAC + b"\xfd\x01" in wire, wire  # ECHO
                    assert IAC + b"\xfd\x03" in wire, wire  # SGA
                    if binary_mode:
                        conn.sendall(IAC + b"\xfd\x00" + IAC + b"\xfb\x00")
                        # Acknowledge BINARY before sending high bytes.
                        time.sleep(0.1)
                    conn.sendall(b"from-server\r\n")
                    until(read, b"from-server")
                    payload = b"from-client\r" if not binary_mode else b"byte-\x80-\xff\r"
                    os.write(fd, payload)
                    until(netread, b"from-client\r\x00" if not binary_mode else b"byte-\x80-\xff\xff")
                    assert IAC + b"\xfd\x01" in wire, wire  # ECHO
                    assert IAC + b"\xfd\x03" in wire, wire  # SGA
                    if binary_mode:
                        conn.sendall(b"peer-\x80-\xff\xff-END")
                        until(read, b"peer-\x80-\xff-END")
                    # Enter command mode and explicitly close the test connection.
                    os.write(fd, b"\x1d")
                    until(read, b"telnet> ")
                    os.write(fd, b"status\n")
                    until(read, b"Connected to")
                    os.write(fd, b"\x1d")
                    until(read, b"telnet> ")
                    os.write(fd, b"quit\n")
                    assert proc.wait(timeout=5) == 0
            finally:
                stop(proc, fd)
        print("PASS session:", host, term, "binary" if binary_mode else "NVT", "port", number)

    session(socket.AF_INET)
    session(socket.AF_INET6)
    session(socket.AF_INET, binary_mode=True)
    session(socket.AF_INET, term="xterm-kitty")
    session(socket.AF_INET, term="xterm-ghostty")
    session(socket.AF_INET, term="unlisted-terminal")
    session(socket.AF_INET, port=23)  # no /etc/services: default port still works
print("PASS: empty chroot (no loader, libraries, terminfo, shell, /etc or /dev)")
