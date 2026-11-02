#!/usr/bin/env python3
"""下载 astral-sh/python-build-standalone 某个 release 的构建，作为 uv 的 python-install-mirror。

用法:
    ./pbs-download.py 20261026
    ./pbs-download.py https://github.com/astral-sh/python-build-standalone/releases/tag/20261026
    ./pbs-download.py 20261026 --platform aarch64-apple-darwin   # 追加平台
    ./pbs-download.py 20261026 --variant install_only            # 追加变体
    ./pbs-download.py 20261026 --dry-run                         # 只列出不下载
    ./pbs-download.py latest -d /data/mirror/pbs                 # 最新 release，下载到指定目录（适合 crontab）

文件保存到 <目录>/<tag>/<原始文件名>（默认目录为脚本所在目录），对应 uv 请求的 {mirror}/{tag}/{filename}。
已存在且校验通过的文件会跳过；下载完成后按官方 SHA256SUMS 校验。
可选环境变量: GITHUB_TOKEN（避免 API 限流）、HTTPS_PROXY（代理）。
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.request

REPO = "astral-sh/python-build-standalone"
DEFAULT_PLATFORMS = [
    "x86_64-unknown-linux-gnu",
    "aarch64-unknown-linux-gnu",
    "x86_64-pc-windows-msvc",
]
DEFAULT_VARIANTS = ["install_only_stripped"]
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
RETRIES = 5


def parse_tag(arg, ctx):
    if arg.strip() == "latest":
        with open_url(f"https://api.github.com/repos/{REPO}/releases/latest", ctx, api=True) as r:
            return json.load(r)["tag_name"]
    m = re.search(r"/releases/(?:tag|download)/([^/?#]+)", arg)
    tag = m.group(1) if m else arg.strip()
    if not re.fullmatch(r"\d{8}", tag):
        sys.exit(f"无法识别的 release: {arg!r}（应为 8 位日期 tag、release URL 或 latest）")
    return tag


def open_url(url, ctx, api=False):
    headers = {"User-Agent": "pbs-download"}
    if api:
        headers["Accept"] = "application/vnd.github+json"
        if os.environ.get("GITHUB_TOKEN"):
            headers["Authorization"] = "Bearer " + os.environ["GITHUB_TOKEN"]
    for attempt in range(1, RETRIES + 1):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=headers), context=ctx, timeout=60)
        except urllib.error.HTTPError as e:
            if e.code < 500 or attempt == RETRIES:
                raise
        except (urllib.error.URLError, OSError):
            if attempt == RETRIES:
                raise
        time.sleep(2 * attempt)


def list_assets(tag, ctx):
    with open_url(f"https://api.github.com/repos/{REPO}/releases/tags/{tag}", ctx, api=True) as r:
        release_id = json.load(r)["id"]
    assets, page = [], 1
    while True:
        url = f"https://api.github.com/repos/{REPO}/releases/{release_id}/assets?per_page=100&page={page}"
        with open_url(url, ctx, api=True) as r:
            batch = json.load(r)
        assets += batch
        if len(batch) < 100:
            return assets
        page += 1


def select(assets, platforms, variants):
    pat = re.compile(
        r"^cpython-[^-]+-(%s)-(freethreaded-)?(%s)\.tar\.gz$"
        % ("|".join(map(re.escape, platforms)), "|".join(map(re.escape, variants)))
    )
    return [a for a in assets if pat.match(a["name"])]


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(asset, dest_dir, sums, ctx):
    name = asset["name"]
    path = os.path.join(dest_dir, name)
    expected = sums.get(name)
    if os.path.isfile(path) and (expected is None or sha256_of(path) == expected):
        return name, "skip"
    part = path + ".part"
    for attempt in range(1, RETRIES + 1):
        try:
            with open_url(asset["browser_download_url"], ctx) as r, open(part, "wb") as f:
                for chunk in iter(lambda: r.read(1 << 20), b""):
                    f.write(chunk)
            break
        except OSError:
            if attempt == RETRIES:
                raise
            time.sleep(2 * attempt)
    if expected and sha256_of(part) != expected:
        os.remove(part)
        return name, "BAD-SHA256"
    os.replace(part, path)
    return name, "ok"


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("release", help="release tag（如 20261026）、GitHub release URL 或 latest")
    p.add_argument("--platform", action="append", default=[], help="追加平台 triple，可多次指定")
    p.add_argument("--variant", action="append", default=[], help="追加变体（如 install_only），可多次指定")
    p.add_argument("-j", "--jobs", type=int, default=4, help="并发数（默认 4）")
    p.add_argument("-d", "-o", "--dir", "--output", dest="output", default=BASE_DIR,
                   help="mirror 根目录，文件存到 <目录>/<tag>/ 下（默认脚本所在目录）")
    p.add_argument("-k", "--insecure", action="store_true", help="不校验 TLS 证书")
    p.add_argument("--dry-run", action="store_true", help="只列出将下载的文件")
    args = p.parse_args()

    ctx = ssl._create_unverified_context() if args.insecure else None
    tag = parse_tag(args.release, ctx)
    platforms = DEFAULT_PLATFORMS + args.platform
    variants = DEFAULT_VARIANTS + args.variant

    assets = list_assets(tag, ctx)
    selected = select(assets, platforms, variants)
    if not selected:
        sys.exit(f"{tag} 中没有匹配的文件")
    print(f"release {tag}: 共 {len(assets)} 个 asset，匹配 {len(selected)} 个，"
          f"约 {sum(a['size'] for a in selected) / 2**20:.0f} MB")
    if args.dry_run:
        for a in selected:
            print("  " + a["name"])
        return

    dest_dir = os.path.join(args.output, tag)
    os.makedirs(dest_dir, exist_ok=True)
    sums = {}
    sums_asset = next((a for a in assets if a["name"] == "SHA256SUMS"), None)
    if sums_asset:
        with open_url(sums_asset["browser_download_url"], ctx) as r:
            data = r.read()
        with open(os.path.join(dest_dir, "SHA256SUMS"), "wb") as f:
            f.write(data)
        for line in data.decode().splitlines():
            h, _, n = line.partition("  ")
            sums[n.strip()] = h
    else:
        print("警告: release 中没有 SHA256SUMS，将跳过校验")

    failed = 0
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as ex:
        futures = {ex.submit(download, a, dest_dir, sums, ctx): a["name"] for a in selected}
        for i, fut in enumerate(concurrent.futures.as_completed(futures), 1):
            try:
                name, status = fut.result()
            except Exception as e:
                name, status = futures[fut], f"ERROR {e}"
            if status not in ("ok", "skip"):
                failed += 1
            print(f"[{i}/{len(selected)}] {status:10} {name}")

    print(f"完成: {dest_dir}，失败 {failed} 个")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
