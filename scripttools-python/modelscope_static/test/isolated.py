#!/usr/bin/env python3
"""Test the single file in a glibc-2.17 scratch image with no system Python/CA."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("image", help="Image built using test/Dockerfile.glibc217")
args = parser.parse_args()
results = Path(__file__).resolve().parent / "results"
results.mkdir(exist_ok=True)
work = Path(tempfile.mkdtemp(prefix=f"isolated-{os.uname().machine}-", dir=results))
work.chmod(0o777)
checks = []

for name, network, arguments in [
    ("offline-version", "none", ["--version"]),
    ("offline-help", "none", ["download", "--help"]),
    ("https-model-file", "bridge", [
        "download", "Qwen/Qwen2.5-0.5B-Instruct", "config.json", "--local-dir", "/data/model",
    ]),
    ("https-filtered-snapshot", "bridge", [
        "download", "Qwen/Qwen2.5-0.5B-Instruct", "--local-dir", "/data/snapshot",
        "--include", "config.json", "tokenizer_config.json", "--exclude", "tokenizer_config.json",
    ]),
    ("https-dataset-file", "bridge", [
        "download", "--dataset", "AI-ModelScope/alpaca-gpt4-data-zh", "README.md",
        "--local-dir", "/data/dataset",
    ]),
]:
    command = [
        "docker", "run", "--rm", "--read-only", "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges", "--network", network,
        "--tmpfs", "/tmp:rw,exec,mode=1777", "--env", "HOME=/tmp",
        "--mount", f"type=bind,src={work},dst=/data",
        args.image, *arguments,
    ]
    completed = subprocess.run(command, capture_output=True, text=True, timeout=180)
    (work / f"{name}.log").write_text(
        f"exit={completed.returncode}\n{completed.stdout}\n{completed.stderr}"
    )
    assert completed.returncode == 0, (name, completed.returncode, str(work))
    checks.append(name)
    print(f"PASS {name}", flush=True)

assert json.loads((work / "model/config.json").read_text())["model_type"] == "qwen2"
assert (work / "snapshot/config.json").is_file()
assert not (work / "snapshot/tokenizer_config.json").exists()
assert (work / "dataset/README.md").stat().st_size > 0
(work / "summary.json").write_text(json.dumps({
    "image": args.image, "machine": os.uname().machine,
    "checks": checks, "status": "passed",
}, indent=2) + "\n")
print(f"Results: {work}")
