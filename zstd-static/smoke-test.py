#!/usr/bin/env python3
"""Run pzstd in a chroot with no libraries, shell, or helper programs."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

pzstd, zstd = map(os.path.abspath, sys.argv[1:])
with tempfile.TemporaryDirectory(prefix="pzstd-offline-") as directory:
    root = Path(directory)
    shutil.copy2(pzstd, root / "pzstd")
    (root / "dev").mkdir()
    # Test mode opens /dev/null. A regular sink suffices inside this test root.
    (root / "dev/null").touch()
    data = (bytes(range(256)) * 4096 + b"parallel zstandard\n" * 65536) * 6
    (root / "input").write_bytes(data)

    def enter_root():
        os.chroot(root)
        os.chdir("/")

    def run(*args, input=None, success=True):
        result = subprocess.run(
            ["/pzstd", *args], input=input, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, preexec_fn=enter_root, timeout=180,
        )
        if (result.returncode == 0) != success:
            raise RuntimeError(f"pzstd {args}: exit {result.returncode}: {result.stderr.decode(errors='replace')}")
        return result.stdout

    run("--version")
    run("-p", "2", "-1", "input", "-o", "parallel.zst")
    run("-p", "2", "-d", "parallel.zst", "-o", "restored")
    assert (root / "restored").read_bytes() == data
    run("-p", "2", "-t", "parallel.zst")

    decoded = subprocess.run(
        [zstd, "-q", "-d", "-c", str(root / "parallel.zst")],
        check=True, capture_output=True, timeout=180,
    ).stdout
    assert decoded == data
    subprocess.run(
        [zstd, "-q", "-1", str(root / "input"), "-o", str(root / "standard.zst")],
        check=True, timeout=180,
    )
    assert run("-p", "2", "-d", "-c", "standard.zst") == data

    compressed = run("-p", "2", "-3", "-c", input=data)
    assert run("-p", "2", "-d", "-c", input=compressed) == data
    empty = run("-p", "2", "-c", input=b"")
    assert run("-p", "2", "-d", "-c", input=empty) == b""
    run("-p", "2", "-d", "-c", input=compressed[:len(compressed) // 2], success=False)
    run("-p", "2", "-d", "-c", input=b"not a zstd stream", success=False)
    print("PASS: offline chroot, 2-thread round trip, standard zstd interoperability, pipes, empty input, invalid/truncated input")
