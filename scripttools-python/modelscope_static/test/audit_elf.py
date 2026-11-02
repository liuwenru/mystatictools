#!/usr/bin/env python3
"""Inspect the launcher AND every embedded ELF, using the build venv's PyInstaller."""

import argparse
import json
import platform
from pathlib import Path
import re
import subprocess
import tempfile

from PyInstaller.archive.readers import CArchiveReader

parser = argparse.ArgumentParser()
parser.add_argument("binary", type=Path)
args = parser.parse_args()
binary = args.binary.resolve(strict=True)
results = Path(__file__).resolve().parent / "results"
results.mkdir(exist_ok=True)
work = Path(tempfile.mkdtemp(prefix=f"elf-{platform.machine()}-", dir=results))
archive = CArchiveReader(str(binary))
entries = [("modelscope", binary)]
for name, entry in archive.toc.items():
    if entry[-1] == "b":
        data = archive.extract(name)
        if data.startswith(b"\x7fELF"):
            path = work / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            entries.append((name, path))

report = []
for name, path in entries:
    output = subprocess.check_output(
        ["readelf", "-W", "-h", "-l", "-d", "-V", str(path)], text=True,
    )
    (work / (name.replace("/", "_") + ".readelf.txt")).write_text(output)
    machine = re.search(r"Machine:\s+(.+)", output).group(1)
    if platform.machine() == "x86_64":
        assert "X86-64" in machine, (name, machine)
    else:
        assert "AArch64" in machine, (name, machine)
    versions = [tuple(map(int, v.split("."))) for v in re.findall(r"GLIBC_(\d+(?:\.\d+)+)", output)]
    maximum = max(versions, default=(0,))
    needed = re.findall(r"Shared library: \[(.+?)\]", output)
    interpreter = re.findall(r"Requesting program interpreter: (.+?)\]", output)
    stack = re.search(r"GNU_STACK.*", output)
    assert maximum <= (2, 17), (name, maximum)
    assert stack and "RWE" not in stack.group(), (name, "executable or missing GNU_STACK")
    # Do not silently ship host libraries that bypass the intended old-glibc baseline.
    assert not any(n in needed for n in ("libpython3.12.so.1.0", "libssl.so.3", "libcrypto.so.3")), (name, needed)
    if name == "modelscope":
        assert "libz.so.1" not in needed, "bootloader must not need system zlib before extraction"
    report.append({
        "file": name, "machine": machine, "max_glibc": ".".join(map(str, maximum)),
        "needed": needed, "interpreter": interpreter,
    })

(work / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"PASS {len(report)} ELF files; glibc <= 2.17; non-executable stacks; matching architecture")
print(f"Results: {work}")
