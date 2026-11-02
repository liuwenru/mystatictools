#!/usr/bin/env python3
"""在无共享库、shell、辅助程序的临时 chroot 中测试；需要 root 和 openssl 命令。"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time

binary = Path(sys.argv[1]).resolve()
port_base = 25201


def wait_listening(server, port):
    # 不能用探测连接判断就绪：-1 模式会把探测连接当作唯一一次测试。
    # 服务端输出到管道时不保证及时刷新，改为从内核查看 LISTEN 状态。
    suffix = f":{port:04X}"
    for _ in range(200):
        if server.poll() is not None:
            raise AssertionError("server exited\n" + server.stdout.read().decode(errors="replace"))
        for table in ("/proc/net/tcp", "/proc/net/tcp6"):
            try:
                lines = Path(table).read_text().splitlines()[1:]
            except FileNotFoundError:
                continue
            fields = [line.split() for line in lines]
            if any(f[1].endswith(suffix) and f[3] == "0A" for f in fields):
                return
        time.sleep(0.05)
    raise AssertionError(f"server port {port} not listening")


def kernel_supports(family, proto=0, kind=socket.SOCK_STREAM, addr=None):
    try:
        with socket.socket(family, kind, proto) as s:
            if addr:
                s.bind(addr)
        return True
    except OSError:
        return False


with tempfile.TemporaryDirectory(prefix="iperf3-test-") as directory:
    root = Path(directory)
    for d in ("work", "dev", "etc"):
        (root / d).mkdir()
    (root / "tmp").mkdir(mode=0o1777)
    (root / "dev/null").touch()
    # 仅供功能测试的有限随机种子文件，不是可部署的随机数设备。
    (root / "dev/urandom").write_bytes(os.urandom(1 << 20))
    (root / "etc/hosts").write_text("127.0.0.1 iperf-test-host\n")
    shutil.copy2(binary, root / "iperf3")

    # 认证测试用的一次性密钥和用户文件，只存在于临时目录。
    work = root / "work"
    subprocess.run(["openssl", "genrsa", "-out", work / "private.pem", "2048"],
                   check=True, capture_output=True)
    subprocess.run(["openssl", "rsa", "-in", work / "private.pem", "-pubout",
                    "-out", work / "public.pem"], check=True, capture_output=True)
    digest = hashlib.sha256(b"{mario}luigi").hexdigest()
    (work / "users.csv").write_text(f"mario,{digest}\n")

    def enter_chroot():
        os.chroot(root)
        os.chdir("/work")

    def start(*args, env=None):
        return subprocess.Popen(
            ["/iperf3", *args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            preexec_fn=enter_chroot, env=env or {"LC_ALL": "C"},
        )

    def run(*args, success=True, env=None):
        result = subprocess.run(
            ["/iperf3", *args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            preexec_fn=enter_chroot, env=env or {"LC_ALL": "C"}, timeout=60,
        )
        if (result.returncode == 0) != success:
            raise AssertionError(f"iperf3 {args}: exit {result.returncode}\n"
                                 + result.stdout.decode(errors="replace"))
        return result.stdout.decode(errors="replace")

    def client_test(name, client_args, server_args=(), host="127.0.0.1",
                    env=None, success=True):
        global port_base
        port = port_base
        port_base += 1
        server = start("-s", "-1", "-p", str(port), *server_args)
        try:
            wait_listening(server, port)
            out = run("-c", host, "-p", str(port), "-t", "1", "-J", *client_args,
                      success=success, env=env)
        finally:
            try:
                server.wait(timeout=15)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
        if success:
            result = json.loads(out)
            print(f"PASS: {name}", flush=True)
            return result
        print(f"PASS: {name} rejected as expected", flush=True)
        return out

    version = run("--version")
    print(version, flush=True)
    assert "iperf 3.22" in version, version
    for feature in ("SCTP", "authentication", "TCP congestion algorithm setting",
                    "sendfile / zerocopy", "POSIX threads"):
        assert feature in version, feature

    r = client_test("TCP", [])
    assert r["end"]["sum_received"]["bytes"] > 0
    r = client_test("TCP hostname from /etc/hosts", [], host="iperf-test-host")
    assert r["end"]["sum_received"]["bytes"] > 0
    r = client_test("TCP reverse", ["-R"])
    assert r["end"]["sum_received"]["bytes"] > 0
    r = client_test("TCP bidir", ["--bidir"])
    assert r["end"]["sum_received_bidir_reverse"]["bytes"] > 0
    r = client_test("TCP 4 parallel streams", ["-P", "4"])
    assert len(r["end"]["streams"]) == 4
    r = client_test("TCP zerocopy (sendfile)", ["-Z"])
    assert r["end"]["sum_received"]["bytes"] > 0
    r = client_test("TCP congestion reno", ["-C", "reno"])
    assert r["end"]["sender_tcp_congestion"] == "reno", r["end"]
    r = client_test("TCP MSS/window/omit", ["-M", "1200", "-w", "256K", "-O", "1"])
    assert r["end"]["sum_received"]["bytes"] > 0
    r = client_test("UDP 100M", ["-u", "-b", "100M"])
    udp = r["end"]["sum"]
    assert udp["packets"] > 0 and udp["lost_percent"] < 50, udp
    r = client_test("UDP reverse", ["-u", "-b", "20M", "-R"])
    assert r["end"]["sum"]["packets"] > 0

    log = run("-c", "127.0.0.1", "-p", "1", "-t", "1", success=False)
    assert "unable to connect" in log or "Connection refused" in log, log
    print("PASS: connection refused reported", flush=True)

    auth_server = ["--rsa-private-key-path", "private.pem",
                   "--authorized-users-path", "users.csv"]
    auth_client = ["--username", "mario", "--rsa-public-key-path", "public.pem"]
    r = client_test("RSA authentication", auth_client, auth_server,
                    env={"LC_ALL": "C", "IPERF3_PASSWORD": "luigi"})
    assert r["end"]["sum_received"]["bytes"] > 0
    client_test("RSA authentication wrong password", auth_client, auth_server,
                env={"LC_ALL": "C", "IPERF3_PASSWORD": "wrong"}, success=False)

    if kernel_supports(socket.AF_INET6, addr=("::1", 0)):
        r = client_test("TCP IPv6", ["-6"], host="::1")
        assert r["end"]["sum_received"]["bytes"] > 0
    else:
        print("SKIP: IPv6 loopback unavailable in build environment", flush=True)

    if kernel_supports(socket.AF_INET, socket.IPPROTO_SCTP):
        r = client_test("SCTP", ["--sctp"])
        assert r["end"]["sum_received"]["bytes"] > 0
    else:
        print("SKIP: kernel SCTP unavailable in build environment", flush=True)

    leftovers = list((root / "tmp").iterdir())
    assert not leftovers, leftovers
    print("PASS: no temporary files left in /tmp", flush=True)
