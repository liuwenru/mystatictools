#!/usr/bin/env python3
"""Download-only CLI using ModelScope's official command implementations."""

import argparse
import importlib.metadata
import logging
import multiprocessing
import os
import sys

import certifi
from modelscope_hub.cli.download import DownloadCommand
from modelscope_hub.cli.login import LoginCommand, LogoutCommand, WhoamiCommand
from modelscope_hub.errors import HubError, InvalidParameter, NotSupportedError


def main():
    os.environ.setdefault("SSL_CERT_FILE", certifi.where())
    parser = argparse.ArgumentParser(
        description="ModelScope download-only standalone CLI (no inference/training)."
    )
    parser.add_argument(
        "--version", "-V", action="version",
        version=(
            f"modelscope {importlib.metadata.version('modelscope')} "
            f"(modelscope-hub {importlib.metadata.version('modelscope-hub')}; download-only)"
        ),
    )
    parser.add_argument("--token", help="API token; prefer MODELSCOPE_API_TOKEN to avoid shell history.")
    parser.add_argument("--endpoint", help="ModelScope API endpoint.")
    parser.add_argument("--verbose", "-v", action="store_true", help="Show debug logs and traceback.")
    commands = parser.add_subparsers(dest="command", required=True)
    for command in (DownloadCommand, LoginCommand, LogoutCommand, WhoamiCommand):
        command.register(commands)
    args = parser.parse_args()
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )
    try:
        args._command(args).execute()
    except KeyboardInterrupt:
        print("error: Interrupted.", file=sys.stderr)
        return 130
    except (InvalidParameter, NotSupportedError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    except HubError as exc:
        print(f"error: {exc}", file=sys.stderr)
        if args.verbose:
            raise
        return 1
    return 0


if __name__ == "__main__":
    multiprocessing.freeze_support()
    sys.exit(main())
