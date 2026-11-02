#!/usr/bin/env python3
"""Native end-to-end checks; uses only the test host's Python standard library."""

import argparse
import json
import os
import platform
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

SCRIPT_NAME = "benchmark_response_stats.py"

# Replaces the external script to prove stdlib modules not used by the original
# script still import without a rebuild. zoneinfo is excluded: it needs tzdata.
STDLIB_CHECK = r'''
import bz2, csv, ctypes, datetime, decimal, email.mime.text, gzip, hashlib, http.client
import json, lzma, multiprocessing, sqlite3, ssl, tarfile, unicodedata, urllib.request
import uuid, xml.etree.ElementTree as ET, zipfile, zlib
from concurrent.futures import ThreadPoolExecutor
import sys

db = sqlite3.connect(":memory:")
assert db.execute("select 6 * 7").fetchone()[0] == 42
assert lzma.decompress(lzma.compress(b"x" * 100)) == b"x" * 100
assert bz2.decompress(bz2.compress(b"y")) == b"y"
assert zlib.decompress(zlib.compress(b"z")) == b"z"
assert ET.fromstring("<a><b/></a>").find("b") is not None
with ThreadPoolExecutor(2) as pool:
    assert list(pool.map(abs, [-1, -2])) == [1, 2]
print(json.dumps({
    "python": sys.version.split()[0],
    "openssl": ssl.OPENSSL_VERSION,
    "sqlite": sqlite3.sqlite_version,
    "sha256": hashlib.sha256(b"abc").hexdigest(),
    "argv": sys.argv[1:],
}))
'''


def write_sample(path):
    """/a has 1..100 for exact expected values; one line has a Chinese URL."""
    lines = []
    for value in range(1, 101):
        lines.append(f"/a 10.0.0.1:80 {value}")
    for value in (0.5, 1.5, 2.5):
        lines.append(f"/b\t10.0.0.2:80\t{value}")
    lines += ["", "/c 10.0.0.2:80", "/d 10.0.0.2:80 abc", "/接口 10.0.0.2:80 3"]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def check_stats(stdout, stderr):
    rows = {line.split()[-1]: line.split() for line in stdout.splitlines() if line.split()}
    # count average median p95 p99 avg_no_top1 avg_no_top5 top1% top5% lift% url
    assert rows["/a"][:10] == [
        "100", "50.500", "50.500", "95.000", "99.000", "50.000", "48.000",
        "1.98%", "9.70%", "5.21%",
    ], rows["/a"]
    assert "/接口" in stdout
    assert "total=104 url_groups=3 server_groups=2 skipped=2" in stderr, stderr
    assert "skipped line 105" in stderr and "skipped line 106" in stderr, stderr


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path, help=f"executable; {SCRIPT_NAME} must be next to it")
    args = parser.parse_args()
    binary = args.binary.resolve(strict=True)
    script = binary.with_name(SCRIPT_NAME)
    results = Path(__file__).resolve().parent / "results"
    results.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix=f"smoke-{platform.machine()}-", dir=results))
    temp = work / "tmp"
    temp.mkdir()
    # Only the two release files; no build venv, system Python path or locale.
    standalone = work / "standalone"
    standalone.mkdir()
    exe = Path(shutil.copy2(binary, standalone / binary.name))
    shutil.copy2(script, standalone / SCRIPT_NAME)
    env = {"PATH": "/usr/bin:/bin", "HOME": str(work), "TMPDIR": str(temp)}
    sample = work / "input.txt"
    write_sample(sample)
    checks = []

    def run(name, arguments, expected=0, executable=exe, extra_env=None):
        completed = subprocess.run(
            [str(executable), *arguments], cwd=work, env={**env, **(extra_env or {})},
            text=True, encoding="utf-8", capture_output=True, timeout=120,
        )
        (work / f"{name}.log").write_text(
            f"exit={completed.returncode}\n{completed.stdout}\n{completed.stderr}", encoding="utf-8"
        )
        if completed.returncode != expected:
            raise AssertionError(f"{name}: expected exit {expected}, got {completed.returncode}; see {work}")
        checks.append(name)
        print(f"PASS {name}", flush=True)
        return completed

    help_text = run("help", ["--help"]).stdout
    assert "用法:" in help_text and "位置参数:" in help_text and "长尾指标说明" in help_text

    frozen = run("stats", [str(sample)])
    check_stats(frozen.stdout, frozen.stderr)
    # The same script under the host's Python must print identical results.
    reference = subprocess.run(
        [sys.executable, "-I", str(script), str(sample)],
        text=True, encoding="utf-8", capture_output=True, check=True,
    )
    assert (frozen.stdout, frozen.stderr) == (reference.stdout, reference.stderr)
    checks.append("same-as-host-python")
    print("PASS same-as-host-python", flush=True)

    c_locale = run("stats-c-locale", [str(sample)], extra_env={"LANG": "C", "LC_ALL": "C"})
    check_stats(c_locale.stdout, c_locale.stderr)
    run("relative-path-other-cwd", ["input.txt"])
    # The link lives in a local temp dir: the shared SSHFS mount cannot readlink.
    with tempfile.TemporaryDirectory() as link_dir:
        via_link = Path(link_dir) / "link"
        via_link.symlink_to(exe)
        run("symlink-finds-script", [str(sample)], executable=via_link)

    assert "No such file" in run("missing-input", ["missing.txt"], expected=2).stderr
    empty = work / "empty.txt"
    empty.write_text("\n", encoding="utf-8")
    assert "no valid records found" in run("no-valid-records", [str(empty)], expected=2).stderr
    run("no-arguments", [], expected=2)
    bad = work / "bad.txt"
    bad.write_bytes(b"/a 10.0.0.1:80 \xff\xfe\n")
    run("invalid-utf8", [str(bad)], expected=2)

    no_script = work / "no-script"
    no_script.mkdir()
    lone = Path(shutil.copy2(binary, no_script / binary.name))
    assert "external script not found" in run("missing-script", [], expected=1, executable=lone).stderr

    # Edit the external script without rebuilding the executable.
    (no_script / SCRIPT_NAME).write_text(STDLIB_CHECK, encoding="utf-8")
    info = json.loads(run("edited-script-stdlib", ["arg1", "参数"], executable=lone).stdout)
    assert info["python"] == "3.12.15", info
    assert info["argv"] == ["arg1", "参数"], info
    assert info["sha256"].startswith("ba7816bf"), info

    (work / "summary.json").write_text(json.dumps({
        "binary": str(binary), "machine": platform.machine(),
        "checks": checks, "edited_script": info, "status": "passed",
    }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Results: {work}")


if __name__ == "__main__":
    main()
