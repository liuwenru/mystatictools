#!/usr/bin/env python3
"""在没有共享库、shell 和 locale 数据的 chroot 中验证独立运行。"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

artifact = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="dos2unix-test-") as temporary:
    root = Path(temporary)
    for name in ("dos2unix", "unix2dos"):
        shutil.copy2(artifact / name, root / name)
    (root / "mac2unix").symlink_to("dos2unix")
    (root / "unix2mac").symlink_to("unix2dos")

    def enter_root():
        os.chroot(root)
        os.chdir("/")

    def run(name, *args, data=None):
        result = subprocess.run(
            [f"/{name}", *args], input=data, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, env={"LANG": "C.UTF-8"},
            preexec_fn=enter_root, timeout=30,
        )
        if result.returncode:
            raise AssertionError(f"{name} {args}: {result.stderr!r}")
        return result.stdout

    assert run("dos2unix", data=b"a\r\nb\r\n") == b"a\nb\n"
    assert run("unix2dos", data=b"a\nb\n") == b"a\r\nb\r\n"
    assert run("mac2unix", data=b"a\rb\r") == b"a\nb\n"
    assert run("unix2mac", data=b"a\nb\n") == b"a\rb\r"
    assert run("dos2unix", data=b"") == b""
    text = "中文测试\r\n第二行\r\n"
    expected = text.replace("\r\n", "\n").encode()
    for bom, encoding in ((b"\xff\xfe", "utf-16-le"), (b"\xfe\xff", "utf-16-be")):
        (root / "utf16.txt").write_bytes(bom + text.encode(encoding))
        run("dos2unix", "utf16.txt")
        assert (root / "utf16.txt").read_bytes() == expected
    assert run("dos2unix", data=b"\xef\xbb\xbfhello\r\n") == b"hello\n"
    assert run("dos2unix", "-e", data=b"last line") == b"last line\n"

    source = root / "input.txt"
    source.write_bytes(b"one\r\ntwo\r\n")
    os.utime(source, (1600000000, 1600000000))
    run("dos2unix", "-k", "input.txt")
    assert source.read_bytes() == b"one\ntwo\n"
    assert source.stat().st_mtime == 1600000000
    run("unix2dos", "-n", "input.txt", "output.txt")
    assert source.read_bytes() == b"one\ntwo\n"
    assert (root / "output.txt").read_bytes() == b"one\r\ntwo\r\n"

    binary = root / "binary.bin"
    binary.write_bytes(b"\0\1\2\r\n")
    run("dos2unix", "binary.bin")
    assert binary.read_bytes() == b"\0\1\2\r\n"
    (root / "link.txt").symlink_to("input.txt")
    run("dos2unix", "link.txt")
    assert (root / "link.txt").is_symlink()
    print("PASS: isolated CRLF/LF/CR, stdio, UTF-8/UTF-16, BOM, empty input, "
          "add-eol, in-place, paired output, timestamps, binary/symlink safety")
