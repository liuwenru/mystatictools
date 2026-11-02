#!/usr/bin/env python3
"""循环调用 MiniMax HTTPS 接口，生成可被 run.sh + http_export.lua 解密的流量

用法：
    export MINIMAX_API_KEY=eyJ...
    export SSLKEYLOGFILE=/root/python-tls.keys     # 给本进程
    ./run.sh capture ens192 out.pcap out.txt 443 &  # 用户自行启动
    python3 mock_minimax.py [--count 5] [--prompt "..."] [--model MiniMax-M3]

脚本只负责循环发请求，PCAP 抓包和离线解密由 run.sh 完成。
"""

from __future__ import annotations

import argparse
import json
import os
import ssl
import sys
import time
from pathlib import Path

import http.client

DEFAULT_API_HOST = "api.minimaxi.com"
DEFAULT_API_PATH = "/v1/chat/completions"
DEFAULT_MODEL = "MiniMax-M3"
DEFAULT_KEYLOG = "/root/python-tls.keys"


def build_ssl_context(keylog: str) -> ssl.SSLContext:
    ctx = ssl.create_default_context()
    ctx.check_hostname = True
    ctx.verify_mode = ssl.CERT_REQUIRED
    if keylog:
        ctx.keylog_filename = keylog
    return ctx


def call_once(api_key: str, keylog: str, model: str, prompt: str, timeout: int = 30) -> dict:
    ctx = build_ssl_context(keylog)
    conn = http.client.HTTPSConnection(DEFAULT_API_HOST, 443, context=ctx, timeout=timeout)
    payload = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": prompt},
        ],
        "max_completion_tokens": 128,
        "temperature": 0.2,
        "stream": False,
    })
    try:
        conn.request(
            "POST",
            DEFAULT_API_PATH,
            body=payload,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {api_key}",
                "Accept": "application/json",
                "Accept-Encoding": "identity",
            },
        )
        resp = conn.getresponse()
        body = resp.read().decode("utf-8", errors="replace")
        return {"status": resp.status, "body": body}
    finally:
        conn.close()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=5, help="请求次数")
    ap.add_argument("--interval", type=float, default=1.0, help="两次请求间隔秒")
    ap.add_argument("--prompt", default="用一句话介绍 MiniMax 文本生成接口。")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--keylog", default=os.environ.get("SSLKEYLOGFILE", DEFAULT_KEYLOG))
    ap.add_argument("--timeout", type=int, default=30)
    args = ap.parse_args()

    api_key = os.environ.get("MINIMAX_API_KEY") or os.environ.get("OPENAI_API_KEY")
    if not api_key:
        print("ERROR: 需要 MINIMAX_API_KEY 环境变量", file=sys.stderr)
        return 2

    keylog = args.keylog
    Path(keylog).parent.mkdir(parents=True, exist_ok=True)
    Path(keylog).touch()

    print(f"[setup] host={DEFAULT_API_HOST} model={args.model} keylog={keylog} count={args.count}")

    success = 0
    for i in range(1, args.count + 1):
        t0 = time.time()
        try:
            r = call_once(api_key, keylog, args.model, args.prompt, args.timeout)
            dt = time.time() - t0
            if r["status"] == 200:
                try:
                    j = json.loads(r["body"])
                    content = j.get("choices", [{}])[0].get("message", {}).get("content", "")
                    print(f"[{i}/{args.count}] HTTP {r['status']} {dt:.2f}s reply={content[:160]!r}")
                except json.JSONDecodeError:
                    print(f"[{i}/{args.count}] HTTP {r['status']} {dt:.2f}s body[:160]={r['body'][:160]!r}")
                success += 1
            else:
                print(f"[{i}/{args.count}] HTTP {r['status']} {dt:.2f}s err={r['body'][:200]}")
        except Exception as e:
            print(f"[{i}/{args.count}] EXC {e!r}", file=sys.stderr)
        if i < args.count:
            time.sleep(args.interval)

    print(f"[done] success={success}/{args.count}")
    return 0 if success == args.count else 1


if __name__ == "__main__":
    raise SystemExit(main())