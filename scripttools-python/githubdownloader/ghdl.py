#!/usr/bin/env python3
"""
ghdl - 下载 GitHub 仓库最新 release 中匹配 OS / 架构 (amd64 / arm64) 的资产

用法示例:
  ghdl.py https://github.com/BurntSushi/ripgrep            # 自动识别本机 OS + 架构
  ghdl.py cli/cli --arch arm64 --os linux                   # 指定架构/系统
  ghdl.py sharkdp/fd --list                                 # 只列出资产及打分, 不下载
  ghdl.py junegunn/fzf --dist ~/tools/bin -x               # 下载到指定目录并解压
  ghdl.py owner/repo --tag v1.2.3 --ext .deb                # 指定版本与包格式
环境变量 GITHUB_TOKEN / GH_TOKEN: 可选, 提高 API 限额并支持私有仓库
"""
import argparse
import hashlib
import json
import os
import platform
import re
import sys
import tarfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile

API = "https://api.github.com"

# ---------- 架构 / 系统别名 ----------
ARCH_ALIASES = {
    "amd64": ["x86_64", "x86-64", "amd64", "x64", "64bit", "linux64", "win64"],
    "arm64": ["aarch64", "arm64", "armv8", "arm64-v8a", "aarch_64"],
}
# 出现这些即判定为"其他架构", 直接排除
OTHER_ARCH = ["i386", "i686", "386", "x86", "32bit", "win32", "armv7", "armv7l",
              "armv6", "armhf", "armel", "arm", "riscv64", "s390x", "ppc64le",
              "ppc64", "mips", "mipsle", "mips64", "mips64le", "loong64",
              "loongarch64"]
OS_ALIASES = {
    "linux": ["linux", "unknown-linux-gnu", "unknown-linux-musl"],
    "darwin": ["darwin", "macos", "mac", "osx", "apple"],
    "windows": ["windows", "win", "win64", "win32", "pc-windows", "msvc"],
}
OTHER_OS = ["freebsd", "openbsd", "netbsd", "android", "illumos", "solaris",
            "dragonfly", "aix", "plan9", "ios"]

# 校验/签名/元数据文件, 不作为下载目标
SKIP_RE = re.compile(
    r"(\.(sha\d+|sha\d+sum|md5|sig|asc|pem|crt|sbom|spdx|json|txt|intoto\.jsonl|"
    r"bundle|cdx\.xml|minisig)$)|checksums?|sha\d+sums?|sbom|provenance", re.I)

ARCHIVE_EXT = (".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".tbz", ".tar.zst", ".zip")
PKG_EXT = (".deb", ".rpm", ".apk", ".msi", ".dmg", ".pkg", ".appimage", ".snap", ".exe")


def has_token(name: str, tok: str) -> bool:
    """以非字母数字为边界匹配 token, 避免 'arm' 命中 'arm64' 之类的误判"""
    return re.search(r"(?<![a-z0-9])" + re.escape(tok) + r"(?![a-z0-9])", name) is not None


def detect_os() -> str:
    s = platform.system().lower()
    return {"linux": "linux", "darwin": "darwin", "windows": "windows"}.get(s, s)


def detect_arch() -> str:
    m = platform.machine().lower()
    if m in ("x86_64", "amd64", "x64"):
        return "amd64"
    if m in ("aarch64", "arm64", "armv8l", "armv8"):
        return "arm64"
    sys.exit(f"[x] 无法识别本机架构: {m}, 请用 --arch 指定")


def parse_repo(s: str):
    s = s.strip()
    if s.startswith(("http://", "https://", "github.com/")):
        if not s.startswith("http"):
            s = "https://" + s
        parts = urllib.parse.urlparse(s).path.strip("/").split("/")
    else:
        parts = s.strip("/").split("/")
    if len(parts) < 2:
        sys.exit(f"[x] 无法解析仓库地址: {s}")
    return parts[0], parts[1].removesuffix(".git")


# ---------- HTTP ----------
class _StripAuthOnRedirect(urllib.request.HTTPRedirectHandler):
    """跳转到 objects.githubusercontent / S3 时去掉 Authorization, 否则会 400"""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is not None and urllib.parse.urlparse(newurl).hostname != urllib.parse.urlparse(req.full_url).hostname:
            for h in ("Authorization",):
                new.headers.pop(h, None)
                new.unredirected_hdrs.pop(h, None)
        return new


OPENER = urllib.request.build_opener(_StripAuthOnRedirect)
TOKEN = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")


def request(url, accept="application/vnd.github+json"):
    req = urllib.request.Request(url, headers={"Accept": accept, "User-Agent": "ghdl"})
    if TOKEN and urllib.parse.urlparse(url).hostname == "api.github.com":
        req.add_header("Authorization", f"Bearer {TOKEN}")
    try:
        return OPENER.open(req, timeout=60)
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="ignore")[:300]
        hint = " (可能触发了匿名限额, 设置 GITHUB_TOKEN 试试)" if e.code == 403 else ""
        sys.exit(f"[x] HTTP {e.code} {url}{hint}\n{body}")


def get_json(url):
    with request(url) as r:
        return json.load(r)


def get_release(owner, repo, tag=None, pre=False):
    base = f"{API}/repos/{owner}/{repo}/releases"
    if tag:
        return get_json(f"{base}/tags/{urllib.parse.quote(tag)}")
    if pre:
        rels = [r for r in get_json(f"{base}?per_page=20") if not r.get("draft")]
        if not rels:
            sys.exit("[x] 该仓库没有 release")
        return rels[0]
    return get_json(f"{base}/latest")


# ---------- 资产打分 ----------
def score_asset(name, want_os, want_arch, ext=None, libc=None):
    """返回 (分数, 原因); 分数为 None 表示排除"""
    n = name.lower()
    if SKIP_RE.search(n):
        return None, "校验/签名/元数据文件"
    if ext and not n.endswith(ext.lower()):
        return None, f"扩展名不是 {ext}"

    score = 0
    # --- OS ---
    os_hit = [o for o, al in OS_ALIASES.items() if any(has_token(n, a) for a in al)]
    if any(has_token(n, o) for o in OTHER_OS):
        return None, "其他操作系统"
    if os_hit:
        if want_os not in os_hit:
            return None, f"系统不符 ({'/'.join(os_hit)})"
        score += 20
    elif want_os == "windows" and n.endswith((".exe", ".msi")):
        score += 15
    elif want_os == "darwin" and n.endswith((".dmg", ".pkg")):
        score += 15
    elif want_os == "linux" and n.endswith((".deb", ".rpm", ".apk", ".appimage")):
        score += 15

    # --- 架构 ---
    arch_hit = [a for a, al in ARCH_ALIASES.items() if any(has_token(n, x) for x in al)]
    # win64 / linux64 这类既是 OS 又暗含 amd64 的情况, 若同时出现 arm64 以 arm64 为准
    if "arm64" in arch_hit and "amd64" in arch_hit:
        arch_hit = ["arm64"]
    if arch_hit:
        if want_arch not in arch_hit:
            return None, f"架构不符 ({'/'.join(arch_hit)})"
        score += 30
    elif any(has_token(n, x) for x in OTHER_ARCH):
        return None, "其他架构"
    elif (want_os == "darwin" and has_token(n, "universal")) or has_token(n, "noarch"):
        score += 20  # macOS universal 二进制 / noarch
    else:
        score += 0   # 名字里没写架构, 作为兜底候选

    # --- libc ---
    if has_token(n, "musl"):
        score += 3 if libc == "musl" else -2
    elif has_token(n, "gnu") and libc == "gnu":
        score += 3

    # --- 包格式偏好: 压缩包 > 裸二进制 > 安装包 ---
    if n.endswith(ARCHIVE_EXT):
        score += 5
    elif n.endswith(PKG_EXT):
        score += 1
    elif "." not in n.rsplit("/", 1)[-1][-6:]:
        score += 3  # 裸二进制
    return score, ""


def pick(assets, want_os, want_arch, ext, libc):
    ranked, skipped = [], []
    for a in assets:
        s, why = score_asset(a["name"], want_os, want_arch, ext, libc)
        (skipped if s is None else ranked).append((s, a, why))
    ranked.sort(key=lambda t: (-t[0], len(t[1]["name"])))
    return ranked, skipped


# ---------- 下载 / 校验 / 解压 ----------
def download(asset, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, asset["name"])
    if TOKEN:  # 走 API 地址, 私有仓库也能下
        resp = request(asset["url"], accept="application/octet-stream")
    else:
        resp = request(asset["browser_download_url"], accept="*/*")
    total = int(resp.headers.get("Content-Length") or asset.get("size") or 0)
    h, done = hashlib.sha256(), 0
    with resp, open(path, "wb") as f:
        while chunk := resp.read(1 << 16):
            f.write(chunk)
            h.update(chunk)
            done += len(chunk)
            if total and sys.stderr.isatty():
                pct = done * 100 // total
                sys.stderr.write(f"\r    {pct:3d}%  {done/1048576:.1f}/{total/1048576:.1f} MiB")
    if sys.stderr.isatty():
        sys.stderr.write("\n")
    return path, h.hexdigest()


def find_expected_sha256(asset, assets):
    # 1) GitHub 2025 起在 API 中直接提供 digest 字段
    d = asset.get("digest") or ""
    if d.startswith("sha256:"):
        return d.split(":", 1)[1], "GitHub digest"
    # 2) 同名 .sha256 / checksums.txt
    name = asset["name"]
    cands = [a for a in assets if a["name"] in (name + ".sha256", name + ".sha256sum")]
    cands += [a for a in assets if re.search(r"(checksums?|sha256sums?)(\.txt)?$", a["name"], re.I)]
    for c in cands:
        with request(c["browser_download_url"], accept="*/*") as r:
            text = r.read().decode(errors="ignore")
        for line in text.splitlines():
            m = re.match(r"^([a-fA-F0-9]{64})\s+\*?(\S+)?", line.strip())
            if m and (m.group(2) is None or os.path.basename(m.group(2)) == name):
                return m.group(1).lower(), c["name"]
    return None, None


def extract(path, out_dir):
    n = path.lower()
    if n.endswith(".zip"):
        with zipfile.ZipFile(path) as z:
            z.extractall(out_dir)
    elif re.search(r"\.(tar\.(gz|xz|bz2)|tgz|txz|tbz)$", n):
        with tarfile.open(path) as t:
            if hasattr(tarfile, "data_filter"):
                t.extractall(out_dir, filter="data")  # 防路径穿越
            else:
                t.extractall(out_dir)
    else:
        print(f"[!] {os.path.basename(path)} 不是可解压的归档, 跳过解压")
        return
    print(f"[+] 已解压到 {out_dir}")


# ---------- 帮助文本 ----------
HELP_DESC = """\
ghdl - 从 GitHub Release 下载与目标平台匹配的二进制文件

根据仓库地址获取 release (默认最新正式版), 按 操作系统 + CPU 架构 (amd64/arm64)
自动挑选最合适的资产文件下载, 并进行 sha256 校验, 可选自动解压."""

HELP_EPILOG = """\
示例:
  ghdl https://github.com/BurntSushi/ripgrep         # 自动识别本机平台下载
  ghdl cli/cli --os linux --arch arm64               # 为 ARM 服务器下载 Linux 版
  ghdl junegunn/fzf --dist ~/tools/bin -x            # 下载到指定目录并解压
  ghdl sharkdp/fd --list                             # 查看候选文件及打分
  ghdl owner/repo --tag v1.2.3 --ext .deb            # 指定版本和包格式
  ghdl owner/repo --libc musl -d ./alpine            # Alpine 用 musl 版

匹配规则:
  1. 排除校验/签名/元数据文件 (.sha256, checksums.txt, .sig, .asc, sbom 等)
  2. 文件名包含其他系统 (freebsd/android 等) 或其他架构 (386/armv7/riscv64 等) 的直接排除
  3. 系统命中 +20, 架构命中 +30; macOS universal 包视为架构兼容
  4. 格式加分: 压缩包 +5, 裸二进制 +3, 安装包 +1
  5. 取最高分; 分数 < 50 会提示可能不准, 同分会列出供参考

环境变量:
  GITHUB_TOKEN / GH_TOKEN   GitHub 访问令牌 (可选)
                            匿名 API 限额为 60 次/小时, 设置后提升至 5000 次/小时,
                            并可下载私有仓库的 release

退出码:
  0  成功
  1  出错 (网络/HTTP 错误、无匹配资产、sha256 不一致等)
  2  参数错误 (缺少 REPO、选项取值非法等)"""


# ---------- main ----------
def main():
    p = argparse.ArgumentParser(
        prog="ghdl",
        formatter_class=lambda prog: argparse.RawTextHelpFormatter(prog, max_help_position=34),
        usage="%(prog)s REPO [选项]",
        description=HELP_DESC,
        epilog=HELP_EPILOG,
        add_help=False,
    )
    g = p.add_argument_group("位置参数")
    g.add_argument("repo", metavar="REPO",
                   help="仓库地址, 支持以下写法:\n"
                        "  https://github.com/owner/repo\n"
                        "  github.com/owner/repo\n"
                        "  owner/repo")

    g = p.add_argument_group("平台匹配")
    g.add_argument("--arch", choices=["amd64", "arm64"], metavar="{amd64,arm64}",
                   help="目标 CPU 架构 (默认: 自动检测本机)\n"
                        "  amd64 匹配: x86_64 / x86-64 / amd64 / x64 / 64bit\n"
                        "  arm64 匹配: aarch64 / arm64 / armv8")
    g.add_argument("--os", dest="os_", choices=["linux", "darwin", "windows"],
                   metavar="{linux,darwin,windows}",
                   help="目标操作系统 (默认: 自动检测本机)\n"
                        "  darwin 也匹配 macos / osx / apple")
    g.add_argument("--libc", choices=["gnu", "musl"], metavar="{gnu,musl}",
                   help="Linux 下 gnu 与 musl 版本并存时优先哪个\n"
                        "  (默认: 优先 gnu; musl 适合 Alpine / 静态部署)")
    g.add_argument("--ext", metavar="EXT",
                   help="只接受该扩展名的文件, 如 .tar.gz / .zip / .deb / .rpm\n"
                        "  (默认优先级: 压缩包 > 裸二进制 > 安装包)")

    g = p.add_argument_group("版本选择")
    g.add_argument("--tag", metavar="TAG",
                   help="下载指定 tag 的 release, 如 v1.2.3 (默认: latest)")
    g.add_argument("--pre", action="store_true",
                   help="允许预发布版本, 取最新一个非 draft 的 release\n"
                        "  (默认 latest 接口会跳过 pre-release)")

    g = p.add_argument_group("输出")
    g.add_argument("-d", "--dist", "-o", "--output", dest="output", default=".", metavar="DIR",
                   help="下载目录, 不存在会自动创建 (默认: 当前目录)")
    g.add_argument("-x", "--extract", action="store_true",
                   help="下载后解压到 --dist 目录 (支持 zip / tar.gz / tar.xz / tar.bz2)")
    g.add_argument("-l", "--list", action="store_true",
                   help="只列出全部资产、打分与排除原因, 不下载 (调试匹配用)")
    g.add_argument("--no-verify", action="store_true",
                   help="跳过 sha256 校验 (默认: 有校验信息就校验, 不一致则删除文件)")
    g.add_argument("-h", "--help", action="help", help="显示本帮助并退出")
    a = p.parse_args()

    owner, repo = parse_repo(a.repo)
    want_os, want_arch = a.os_ or detect_os(), a.arch or detect_arch()
    rel = get_release(owner, repo, a.tag, a.pre)
    assets = rel.get("assets", [])
    print(f"[*] {owner}/{repo}  release: {rel.get('tag_name')}  目标: {want_os}/{want_arch}  资产数: {len(assets)}")
    if not assets:
        sys.exit("[x] 该 release 没有上传二进制资产 (可能只有源码包)")

    ranked, skipped = pick(assets, want_os, want_arch, a.ext, a.libc)

    if a.list:
        for s, x, _ in ranked:
            print(f"  {s:>4}  {x['name']}")
        for _, x, why in skipped:
            print(f"     -  {x['name']}   ({why})")
        return

    if not ranked:
        sys.exit("[x] 没有匹配的资产, 用 --list 查看全部文件名")
    best_score, best, _ = ranked[0]
    if best_score < 50:
        print(f"[!] 最佳匹配分数偏低 ({best_score}), 文件名中可能没写系统或架构, 请确认")
    ties = [x["name"] for s, x, _ in ranked[1:] if s == best_score]
    if ties:
        print(f"[!] 同分候选: {', '.join(ties)} (可用 --ext / --libc 收窄)")

    print(f"[+] 选中: {best['name']}  ({best.get('size', 0)/1048576:.1f} MiB)")
    path, actual = download(best, a.output)

    if not a.no_verify:
        expected, src = find_expected_sha256(best, assets)
        if expected is None:
            print("[!] 未找到 sha256 信息, 跳过校验")
        elif expected.lower() != actual:
            os.remove(path)
            sys.exit(f"[x] sha256 不一致! 期望 {expected} 实际 {actual} (来源 {src}), 已删除文件")
        else:
            print(f"[+] sha256 校验通过 (来源: {src})")

    print(f"[+] 已保存: {os.path.abspath(path)}")
    if a.extract:
        extract(path, a.output)


if __name__ == "__main__":
    main()
