#!/usr/bin/env python3
"""用 socketpair 传输；在只有二进制及样例的 chroot 内验证离线运行。需要 root。"""

import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile


# 多个协议和样例重复启动同一组进程，集中处理超时、日志及子进程回收。
def transfer(root, sender, receiver, names, expected):
    def enter_root():
        os.chroot(root)
        os.chdir("/receive")

    left, right = socket.socketpair()
    processes = []
    with tempfile.TemporaryFile() as log:
        try:
            processes.append(subprocess.Popen(
                [*receiver], stdin=left, stdout=left, stderr=log,
                env={"LC_ALL": "C", "PATH": "/nonexistent"}, preexec_fn=enter_root,
            ))
            processes.append(subprocess.Popen(
                [*sender, *names], stdin=right, stdout=right, stderr=log,
                env={"LC_ALL": "C", "PATH": "/nonexistent"}, preexec_fn=enter_root,
            ))
            left.close()
            right.close()
            for process in processes:
                assert process.wait(timeout=45) == 0, f"传输退出异常: {process.args}"
            for name, data in expected.items():
                received = (root / name).read_bytes()
                assert received == data, f"内容不一致: {name}"
        except BaseException:
            log.seek(0)
            print(log.read().decode(errors="replace"), file=sys.stderr)
            raise
        finally:
            left.close()
            right.close()
            for process in processes:
                if process.poll() is None:
                    process.kill()
                process.wait()


binary_dir = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="lrzsz-test-") as temporary:
    root = Path(temporary)
    (root / "bin").mkdir()
    (root / "send").mkdir()
    (root / "receive").mkdir()
    for name in ("lrz", "lsz"):
        shutil.copy2(binary_dir / name, root / "bin" / name)
    for name in ("rz", "rx", "rb", "lrx", "lrb"):
        (root / "bin" / name).symlink_to("lrz")
    for name in ("sz", "sx", "sb", "lsx", "lsb"):
        (root / "bin" / name).symlink_to("lsz")
    for name in ("lrz", "lsz", "rz", "sz", "rx", "sx", "rb", "sb", "lrx", "lsx", "lrb", "lsb"):
        result = subprocess.run(
            ["chroot", str(root), f"/bin/{name}", "--version"],
            capture_output=True, text=True, check=True,
        )
        assert "0.13.1" in result.stdout, result.stdout

    samples = {
        "empty": b"",
        "text.txt": "静态传输测试\nline two\r\n".encode(),
        "binary.bin": bytes(range(256)) * 8192 + b"\x00\xff\x18\x11\x13",
    }
    for name, data in samples.items():
        (root / "send" / name).write_bytes(data)
    for protocol, sender, receiver in (("ZMODEM", "sz", "rz"), ("YMODEM", "sb", "rb")):
        expected = {f"receive/{name}": data for name, data in samples.items()}
        transfer(root, [f"/bin/{sender}", "-b", "--syslog=off"],
                 [f"/bin/{receiver}", "-b", "--syslog=off", "-y"],
                 [f"/send/{name}" for name in samples], expected)
        print(f"PASS {protocol}: 空文件、文本、2 MiB 二进制逐字节一致", flush=True)
        for name in samples:
            (root / "receive" / name).unlink()

    # XMODEM 不传文件长度，使用整块样例，避免把协议填充误判为损坏。
    data = bytes(range(256)) * 16
    (root / "send/x.bin").write_bytes(data)
    transfer(root, ["/bin/sx", "-b", "--syslog=off"],
             ["/bin/rx", "-b", "--syslog=off", "x.bin"],
             ["/send/x.bin"], {"receive/x.bin": data})
    print("PASS XMODEM: 4096 字节二进制逐字节一致", flush=True)

    data = samples["binary.bin"]
    (root / "receive/binary.bin").write_bytes(data[:65536])
    transfer(root, ["/bin/sz", "-b", "-r", "--syslog=off"],
             ["/bin/rz", "-b", "-r", "--syslog=off"],
             ["/send/binary.bin"], {"receive/binary.bin": data})
    print("PASS ZMODEM: 从已有 64 KiB 前缀续传后内容一致", flush=True)
