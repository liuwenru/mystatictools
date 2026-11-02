#!/usr/bin/env python3
"""测试 dist 目录中的 ethtool。

    smoke-test.py DIR            只读测试，只用 lo；构建容器内运行（没有 CAP_NET_ADMIN）。
    unshare -n smoke-test.py DIR --netns
                                 修改类测试：在新的空网络命名空间中创建 veth，需要 root 和 ip 命令。
                                 除 lo 外存在任何网卡时拒绝运行，避免改动真实网卡。
"""
import json
import os
from pathlib import Path
import pty
import select
import shutil
import socket
import subprocess
import sys
import time

out_dir = Path(sys.argv[1]).resolve()
ethtool = str(out_dir / "ethtool")
netns_mode = sys.argv[2:] == ["--netns"]
version = "7.2"


def check(name, condition, detail=""):
    if not condition:
        raise AssertionError(f"{name}\n{detail}")
    print(f"PASS: {name}", flush=True)


def run(*args, code=0):
    result = subprocess.run([ethtool, *args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            env={}, timeout=30)
    out = result.stdout.decode(errors="replace")
    if code is not None and result.returncode != code:
        raise AssertionError(f"ethtool {args}: exit {result.returncode}\n{out}")
    return out


def has_net_admin():
    for line in Path("/proc/self/status").read_text().splitlines():
        if line.startswith("CapEff:"):
            return int(line.split()[1], 16) & (1 << 12) != 0
    return False


def read_only_tests():
    out = run("--version")
    check("version", out.strip() == f"ethtool version {version}", out)
    out = run("-h")
    check("-h usage", "ethtool [ FLAGS ]  DEVNAME" in out and "--monitor" in out, out[:300])

    out = run("lo")
    check("lo link settings via netlink", "Settings for lo:" in out
          and "Link detected: yes" in out, out)
    out = run("-k", "lo")
    check("-k features", "loopback: on [fixed]" in out, out)
    features = json.loads(run("--json", "-k", "lo"))
    check("--json -k", features[0]["ifname"] == "lo"
          and features[0]["loopback"]["active"] is True, features)
    out = run("--disable-netlink", "-k", "lo")
    check("--disable-netlink -k (ioctl path)", "loopback: on [fixed]" in out, out)
    out = run("-T", "lo")
    check("-T timestamping", "software-transmit" in out, out)
    out = run("nosuchdev0", code=None)
    check("unknown device reported", "No such device" in out or "no device matches" in out, out)
    out = run("-i", "lo", "bogus", code=1)
    check("bad argument rejected", "bad command line argument" in out, out)

    if not has_net_admin():
        out = run("-K", "lo", "tso", "off", code=None)
        check("-K without CAP_NET_ADMIN refused", "Operation not permitted" in out, out)

    # 驱动寄存器和光模块 EEPROM 的解析需要真实网卡，这里只确认解析代码已编入。
    data = Path(ethtool).read_bytes()
    check("pretty dump code linked", all(s in data for s in
          (b"ixgbe\0", b"e1000\0", b"hns3\0", b"SFF-8636 Rev 1.5", b"Module temperature")))

    page = (out_dir / "ethtool.8").read_text()
    check("man page", f'"Ethtool version {version}"' in page, page[:200])
    bash = shutil.which("bash")
    if bash:
        completion = out_dir / "ethtool.bash-completion"
        out = subprocess.run([bash, "-c", f"source {completion}; complete -p ethtool"],
                             capture_output=True, text=True, check=True).stdout
        check("bash completion loads", "_ethtool" in out, out)
    else:
        print("SKIP: bash completion, bash not installed", flush=True)


def monitor_features(dev):
    """在伪终端中运行 --monitor（输出到管道时缓冲，被结束时会丢失），修改特性后检查通知。"""
    pid, fd = pty.fork()
    if pid == 0:
        os.execve(ethtool, [ethtool, "--monitor"], {})
    out = b""
    changed = False
    start = time.time()
    while time.time() - start < 10:
        if not changed and b"listening..." in out:
            run("-K", dev, "tso", "off")
            changed = True
        ready, _, _ = select.select([fd], [], [], 0.1)
        if ready:
            try:
                out += os.read(fd, 65536)
            except OSError:
                break
        if b"tcp-segmentation-offload: off" in out:
            break
    os.kill(pid, 9)
    os.waitpid(pid, 0)
    os.close(fd)
    return out.decode(errors="replace")


def netns_tests():
    # /sys/class/net 在 unshare -n 后仍是原命名空间的内容，改用 if_nameindex。
    names = sorted(name for _, name in socket.if_nameindex())
    if names != ["lo"]:
        raise SystemExit(f"拒绝运行：当前网络命名空间不是空的 {names}，请用 unshare -n 运行")
    ip = shutil.which("ip")
    subprocess.run([ip, "link", "add", "va", "numrxqueues", "4", "numtxqueues", "4", "type", "veth",
                    "peer", "name", "vb", "numrxqueues", "4", "numtxqueues", "4"], check=True)
    subprocess.run([ip, "link", "set", "va", "up"], check=True)
    subprocess.run([ip, "link", "set", "vb", "up"], check=True)

    out = run("va")
    check("veth link settings", "Speed: 10000Mb/s" in out and "Link detected: yes" in out, out)
    settings = json.loads(run("--json", "va"))
    check("--json link settings", settings[0]["ifname"] == "va", settings)
    out = run("-i", "va")
    check("-i driver info", "driver: veth" in out, out)
    out = run("--disable-netlink", "-i", "va")
    check("--disable-netlink -i (ioctl path)", "driver: veth" in out, out)
    out = run("-S", "va")
    check("-S statistics", "peer_ifindex:" in out, out)

    run("-K", "va", "tso", "off")
    out = run("-k", "va")
    check("-K tso off", "tcp-segmentation-offload: off" in out, out)
    run("--disable-netlink", "-K", "va", "tso", "on")
    out = run("--disable-netlink", "-k", "va")
    check("--disable-netlink -K tso on (ioctl path)", "tcp-segmentation-offload: on" in out, out)

    run("-L", "va", "rx", "2", "tx", "2")
    channels = json.loads(run("--json", "-l", "va"))[0]
    check("-L/-l channels", channels["rx-max"] >= 4 and channels["rx"] == 2
          and channels["tx"] == 2, channels)

    out = monitor_features("va")
    check("--monitor feature notification", "Features for va" in out
          and "tcp-segmentation-offload: off" in out, out[-500:])

    out = run("-g", "va", code=None)
    check("unsupported operation reported", "Not supported" in out, out)


try:
    if netns_mode:
        netns_tests()
    else:
        read_only_tests()
except AssertionError as error:
    print(f"FAIL: {error}", flush=True)
    sys.exit(1)
