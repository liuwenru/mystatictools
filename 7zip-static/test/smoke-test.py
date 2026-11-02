#!/usr/bin/env python3
"""在无共享库、shell、插件的临时 chroot 中测试；需要 root。"""
import bz2
import gzip
import hashlib
import lzma
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

binary = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="7zip-test-") as directory:
    root = Path(directory)
    (root / "work").mkdir()
    (root / "tmp").mkdir(mode=0o1777)
    (root / "dev").mkdir()
    (root / "dev/null").touch()
    # 仅供功能测试的有限随机种子文件，不是可部署的随机数设备。
    (root / "dev/urandom").write_bytes(os.urandom(65536))
    shutil.copy2(binary, root / "7zz")

    def enter_chroot():
        os.chroot(root)
        os.chdir("/work")

    def run(*args, success=True, data=None):
        result = subprocess.run(
            ["/7zz", *args], input=data, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, preexec_fn=enter_chroot,
            env={"LC_ALL": "C.UTF-8"}, timeout=120,
        )
        if (result.returncode == 0) != success:
            raise AssertionError(f"7zz {args}: exit {result.returncode}\n"
                                 + result.stdout.decode(errors="replace"))
        return result.stdout

    work = root / "work"
    payload = ("离线 7-Zip 测试\n".encode() + bytes(range(256))) * 8192
    files = {"中文 空格.txt": payload, "empty": b"", "nested/data.bin": os.urandom(65536)}
    for name, content in files.items():
        path = work / "input" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)

    assert b"7-Zip (z) 26.05" in run("i")
    formats = run("i")
    for fmt in (b"Rar", b"Rar5", b"7z", b"zip", b"zstd"):
        assert fmt in formats, fmt

    for fmt in ("7z", "zip", "tar"):
        archive = f"test.{fmt}"
        run("a", f"-t{fmt}", "-mmt=2", archive, "input")
        run("t", archive)
        run("l", archive)
        run("x", archive, f"-oout-{fmt}", "-y")
        for name, content in files.items():
            assert (work / f"out-{fmt}" / "input" / name).read_bytes() == content
        print(f"PASS: {fmt} directory roundtrip, Unicode, empty file", flush=True)

    # 独立实现验证 ZIP / gzip / bzip2 / xz 互通。
    with zipfile.ZipFile(work / "test.zip") as archive:
        assert archive.read("input/中文 空格.txt") == payload
    for fmt, encode, decode in (("gzip", gzip.compress, gzip.decompress),
                                ("bzip2", bz2.compress, bz2.decompress),
                                ("xz", lzma.compress, lzma.decompress)):
        (work / "peer").write_bytes(encode(payload))
        assert run("x", f"-t{fmt}", "peer", "-so") == payload
        (work / "plain").write_bytes(payload)
        run("a", f"-t{fmt}", "-sae", f"own-{fmt}", "plain")
        assert decode((work / f"own-{fmt}").read_bytes()) == payload
        print(f"PASS: {fmt} Python interoperability", flush=True)

    for fmt, options in (("7z", ["-mhe=on"]), ("zip", ["-mem=AES256"])):
        archive = f"encrypted.{fmt}"
        run("a", f"-t{fmt}", "-ptest-password", *options, archive, "input")
        run("t", "-ptest-password", archive)
        run("t", "-pwrong-password", archive, success=False)
        run("x", "-ptest-password", archive, f"-odecrypted-{fmt}", "-y")
        for name, content in files.items():
            assert (work / f"decrypted-{fmt}" / "input" / name).read_bytes() == content
        print(f"PASS: {fmt} AES encryption/decryption and wrong password", flush=True)

    run("a", "-t7z", "stream.7z", "-sifrom-stdin", data=payload)
    assert run("x", "stream.7z", "-so") == payload
    (work / "bad.7z").write_bytes((work / "test.7z").read_bytes()[:40])
    run("t", "bad.7z", success=False)
    digest = hashlib.sha256(payload).hexdigest().upper().encode()
    hash_output = run("h", "-scrcSHA256", "plain")
    assert digest in hash_output.upper(), hash_output.decode(errors="replace")
    print("PASS: stdin/stdout, SHA256, truncated archive rejection", flush=True)
    print("PASS: all tests in isolated chroot without shared libraries or external tools", flush=True)
