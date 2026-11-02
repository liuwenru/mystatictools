#!/usr/bin/env python3

import runpy
import sys
from pathlib import Path


SCRIPT_NAME = "benchmark_response_stats.py"


def _collect_pyinstaller_dependencies():
    import benchmark_response_stats


def main():
    if getattr(sys, "frozen", False):
        base_dir = Path(sys.executable).resolve().parent
    else:
        base_dir = Path(__file__).resolve().parent

    script_path = base_dir / SCRIPT_NAME
    if not script_path.is_file():
        print(
            "error: external script not found: {}".format(script_path),
            file=sys.stderr,
        )
        return 1

    sys.path.insert(0, str(base_dir))
    runpy.run_path(str(script_path), run_name="__main__")
    return 0


if __name__ == "__main__":
    sys.exit(main())
