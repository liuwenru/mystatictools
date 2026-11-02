#!/usr/bin/env python3
"""Run the release files in a glibc-2.17 scratch image without network or Python."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from smoke import SCRIPT_NAME, STDLIB_CHECK, check_stats, write_sample

parser = argparse.ArgumentParser()
parser.add_argument("image", help="Image built using test/Dockerfile.glibc217")
parser.add_argument("release_dir", type=Path, help="e.g. dist/linux-amd64")
args = parser.parse_args()
release = args.release_dir.resolve(strict=True)
results = Path(__file__).resolve().parent / "results"
results.mkdir(exist_ok=True)
work = Path(tempfile.mkdtemp(prefix=f"isolated-{os.uname().machine}-", dir=results))
write_sample(work / "input.txt")
edited = work / "edited"
edited.mkdir()
shutil.copy2(release / "benchmark_response_stats", edited)
(edited / SCRIPT_NAME).write_text(STDLIB_CHECK, encoding="utf-8")
work.chmod(0o755)
checks = []


def run(name, command, expected=0):
    completed = subprocess.run([
        "docker", "run", "--rm", "--read-only", "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges", "--network", "none",
        "--tmpfs", "/tmp:rw,exec,mode=1777",
        "--mount", f"type=bind,src={release},dst=/app,readonly",
        "--mount", f"type=bind,src={work},dst=/data,readonly",
        "--entrypoint", command[0], args.image, *command[1:],
    ], capture_output=True, text=True, encoding="utf-8", timeout=120)
    (work / f"{name}.log").write_text(
        f"exit={completed.returncode}\n{completed.stdout}\n{completed.stderr}", encoding="utf-8"
    )
    assert completed.returncode == expected, (name, completed.returncode, str(work))
    checks.append(name)
    print(f"PASS {name}", flush=True)
    return completed


assert "用法:" in run("help", ["/app/benchmark_response_stats", "--help"]).stdout
stats = run("stats", ["/app/benchmark_response_stats", "/data/input.txt"])
check_stats(stats.stdout, stats.stderr)
run("missing-input", ["/app/benchmark_response_stats", "/data/missing.txt"], expected=2)
info = json.loads(run("edited-script-stdlib", ["/data/edited/benchmark_response_stats"]).stdout)
assert info["python"] == "3.12.15", info
(work / "summary.json").write_text(json.dumps({
    "image": args.image, "machine": os.uname().machine,
    "checks": checks, "edited_script": info, "status": "passed",
}, indent=2) + "\n")
print(f"Results: {work}")
