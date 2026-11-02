#!/usr/bin/env python3
"""Native end-to-end checks; uses only the test host's Python standard library."""

import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("binary", type=Path)
args = parser.parse_args()
binary = args.binary.resolve(strict=True)
results = Path(__file__).resolve().parent / "results"
results.mkdir(exist_ok=True)
work = Path(tempfile.mkdtemp(prefix=f"smoke-{platform.system()}-{platform.machine()}-", dir=results))
home = work / "home"
home.mkdir()
temp = work / "tmp"
temp.mkdir()
env = {
    key: value for key, value in os.environ.items()
    if not key.startswith(("MODELSCOPE", "PYTHON", "XDG_"))
}
env.update(HOME=str(home), TMPDIR=str(temp), XDG_CACHE_HOME=str(home / ".cache"))
if os.name == "nt":
    # Only Windows system commands remain on PATH; the child cannot find the
    # build Python/venv, user credentials, or adjacent build-time DLLs.
    appdata = home / "AppData/Roaming"
    localappdata = home / "AppData/Local"
    appdata.mkdir(parents=True)
    localappdata.mkdir(parents=True)
    env.update(USERPROFILE=str(home), APPDATA=str(appdata), LOCALAPPDATA=str(localappdata),
               TEMP=str(temp), TMP=str(temp), PATH=str(Path(os.environ["SystemRoot"]) / "System32"))
    for name in ("VIRTUAL_ENV", "CONDA_PREFIX", "CONDA_DEFAULT_ENV"):
        env.pop(name, None)
    standalone = work / "standalone"
    standalone.mkdir()
    binary = Path(shutil.copy2(binary, standalone / binary.name))

checks = []


def run(name, arguments, expected=0):
    completed = subprocess.run(
        [str(binary), *arguments], cwd=work, env=env,
        text=True, encoding="utf-8", capture_output=True, timeout=180,
    )
    (work / f"{name}.log").write_text(
        f"exit={completed.returncode}\n{completed.stdout}\n{completed.stderr}", encoding="utf-8"
    )
    if completed.returncode != expected:
        raise AssertionError(f"{name}: expected exit {expected}, got {completed.returncode}; see {work}")
    checks.append(name)
    print(f"PASS {name}", flush=True)
    return completed.stdout + completed.stderr


assert "1.40.2" in run("version", ["--version"])
help_text = run("help", ["--help"])
assert "download" in help_text and "pipeline" not in help_text
run("download-help", ["download", "--help"])
run("invalid-command", ["pipeline"], expected=2)
run("empty-login-token", ["login", "--token", " "], expected=2)
run("isolated-logout", ["logout"])

run("model-file-legacy", [
    "download", "--model", "Qwen/Qwen2.5-0.5B-Instruct", "config.json",
    "--local_dir", "model-file",
])
config = json.loads((work / "model-file/config.json").read_text())
assert config["model_type"] == "qwen2"
run("missing-file-error", [
    "download", "Qwen/Qwen2.5-0.5B-Instruct", "modelscope-static-missing-file-check.json",
    "--local-dir", "missing-file",
], expected=1)

run("model-snapshot-filter", [
    "download", "Qwen/Qwen2.5-0.5B-Instruct", "--local-dir", "snapshot",
    "--include", "config.json", "tokenizer_config.json",
    "--exclude", "tokenizer_config.json",
])
assert (work / "snapshot/config.json").is_file()
assert not (work / "snapshot/tokenizer_config.json").exists()
assert not list((work / "snapshot").rglob("*.safetensors"))

run("dataset-file", [
    "download", "--dataset", "AI-ModelScope/alpaca-gpt4-data-zh", "README.md",
    "--local-dir", "dataset",
])
assert (work / "dataset/README.md").stat().st_size > 0
if os.name == "nt":
    run("windows-unicode-path", [
        "download", "Qwen/Qwen2.5-0.5B-Instruct", "config.json",
        "--local-dir", "\u4e2d\u6587 \u8def\u5f84",
    ])
    assert json.loads((work / "\u4e2d\u6587 \u8def\u5f84/config.json").read_text(encoding="utf-8"))["model_type"] == "qwen2"

for name in ("cache-first", "cache-repeat"):
    run(name, [
        "download", "Qwen/Qwen2.5-0.5B-Instruct", "config.json",
        "--cache-dir", "cache",
    ])
cached = list((work / "cache").rglob("config.json"))
assert cached
assert hashlib.sha256(cached[0].read_bytes()).digest() == hashlib.sha256(
    (work / "model-file/config.json").read_bytes()
).digest()

(work / "summary.json").write_text(json.dumps({
    "binary": str(binary), "system": platform.system(), "machine": platform.machine(),
    "checks": checks, "status": "passed",
}, indent=2) + "\n", encoding="utf-8")
print(f"Results: {work}")
