#!/usr/bin/env python3
"""在只有 ncat 的临时 chroot 中测试（无 /bin/sh、共享库、/etc/ssl）；需要 root 和 openssl 命令。

上游 ncat-test.pl 已覆盖监听/连接、--keep-open、--broker、--chat、-e/-c、HTTP 代理、SSL、
访问控制等外部行为；这里补充离线环境相关的部分：没有 shell、证书目录和解释器时的表现，
CA 证书的查找路径，Lua、SOCKS5、/etc/hosts、SCTP、vsock。
"""
import os
from pathlib import Path
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time

out_dir = Path(sys.argv[1]).resolve()
VERSION = "7.993"
count = 0
skipped = []


def check(name, condition, detail=""):
    global count
    if not condition:
        raise AssertionError(f"{name}\n{detail}")
    count += 1
    print(f"PASS: {name}", flush=True)


def skip(name, reason):
    skipped.append(name)
    print(f"SKIP: {name}: {reason}", flush=True)


def free_port(kind=socket.SOCK_STREAM, family=socket.AF_INET, host="127.0.0.1"):
    with socket.socket(family, kind) as s:
        s.bind((host, 0))
        return s.getsockname()[1]


def jail(root):
    def enter():
        os.chroot(root)
        os.chdir("/")
    return enter


def ncat(*args, env=None, root=None, stdin=subprocess.DEVNULL):
    """在 chroot 中启动 ncat；不给 PATH 等环境变量。"""
    return subprocess.Popen(["/ncat", *map(str, args)], stdin=stdin, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, env=env or {}, preexec_fn=jail(root or base))


def run(*args, env=None, root=None, data=b"", code=0, timeout=30):
    p = ncat(*args, env=env, root=root, stdin=subprocess.PIPE)
    out, err = p.communicate(data, timeout=timeout)
    if code is not None and p.returncode != code:
        raise AssertionError(f"ncat {args}: exit {p.returncode}\n{out!r}\n{err.decode(errors='replace')}")
    return out, err.decode(errors="replace"), p.returncode


def wait_port(port, proto="tcp", timeout=10):
    """从内核表判断 LISTEN（tcp 状态 0A）或 UDP 已绑定（状态 07），不发探测连接。"""
    suffix = f":{port:04X}"
    state = "0A" if proto == "tcp" else "07"
    tables = [f"/proc/net/{proto}", f"/proc/net/{proto}6"]
    deadline = time.time() + timeout
    while time.time() < deadline:
        for table in tables:
            try:
                lines = Path(table).read_text().splitlines()[1:]
            except FileNotFoundError:
                continue
            if any(f[1].endswith(suffix) and f[3] == state for f in (line.split() for line in lines)):
                return
        time.sleep(0.05)
    raise AssertionError(f"{proto} port {port} not ready")


def wait_path(path, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if path.exists():
            return
        time.sleep(0.05)
    raise AssertionError(f"{path} not created")


def finish(p, timeout=10):
    try:
        out, err = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        p.kill()
        out, err = p.communicate()
    return out, err.decode(errors="replace")


def recv_all(sock):
    data = b""
    while chunk := sock.recv(65536):
        data += chunk
    return data


def tcp_server(handler, host="127.0.0.1", family=socket.AF_INET, wrap=None):
    """后台单连接 TCP 服务端，返回端口和保存结果的列表。"""
    srv = socket.socket(family, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((host, 0))
    srv.listen(1)
    srv.settimeout(20)
    result = []

    def serve():
        try:
            conn, _ = srv.accept()
            if wrap:
                conn = wrap.wrap_socket(conn, server_side=True)
            with conn:
                conn.settimeout(20)
                result.append(handler(conn))
        except Exception as e:  # noqa: BLE001 - 结果交给主线程检查
            result.append(e)
        finally:
            srv.close()

    t = threading.Thread(target=serve, daemon=True)
    t.start()
    return srv.getsockname()[1], result, t


def echo_upper(conn):
    """读到一行就回复：ncat 代理收到客户端半关闭后会关闭两端，不能等 EOF。"""
    data = b""
    while not data.endswith(b"\n") and (chunk := conn.recv(65536)):
        data += chunk
    conn.sendall(data.upper())
    try:
        if isinstance(conn, ssl.SSLSocket):
            conn.unwrap()  # 交换 close_notify；直接 close 会因未读数据发 RST，客户端丢数据
        else:
            conn.shutdown(socket.SHUT_WR)
    except OSError:
        pass
    return data


def openssl(*args, cwd):
    subprocess.run(["openssl", *args], cwd=cwd, check=True, capture_output=True)


def new_root(name, hosts=True):
    root = work / name
    (root / "etc").mkdir(parents=True)
    shutil.copy2(out_dir / "ncat", root / "ncat")
    if hosts:
        (root / "etc" / "hosts").write_text("127.0.0.1 localhost backend.local wrong.local\n")
    return root


work = Path(tempfile.mkdtemp(prefix="ncat-static-test-"))
try:
    base = new_root("base", hosts=False)
    for d in ("dev", "tmp"):
        (base / d).mkdir()
    check("chroot has no /bin/sh, /lib, /etc/ssl",
          not any((base / p).exists() for p in ("bin", "lib", "usr", "etc/ssl")))

    out, err, _ = run("--version")
    check("ncat --version without PATH", f"Ncat: Version {VERSION} " in (out.decode() + err), out + err.encode())
    out, err, _ = run("-h")
    for opt in ("--ssl-verify", "--lua-exec", "--sctp", "--vsock", "--proxy-type", "--unixsock"):
        check(f"-h lists {opt}", opt in out.decode() + err, out)

    # ---------------- 基本连接 ----------------
    port = free_port()
    srv = ncat("-l", "127.0.0.1", port, "--recv-only")
    wait_port(port)
    with socket.create_connection(("127.0.0.1", port)) as c:
        c.sendall(b"hello listen\n")
    out, err = finish(srv)
    check("TCP listen --recv-only on one socket (local patch)", out == b"hello listen\n", out + err.encode())

    port = free_port()
    srv = ncat("-l", "-k", "-4", port, "--recv-only")
    wait_port(port)
    for word in (b"k1\n", b"k2\n"):
        with socket.create_connection(("127.0.0.1", port)) as c:
            c.sendall(word)
        time.sleep(0.3)
    alive = srv.poll() is None
    srv.kill()
    out, err = finish(srv)
    check("-l -k -4 --recv-only keeps listening", alive and out == b"k1\nk2\n", (alive, out, err))

    port, res, t = tcp_server(echo_upper)
    out, err, _ = run("127.0.0.1", port, data=b"hello connect\n")
    t.join(10)
    check("TCP connect send/receive", res == [b"hello connect\n"] and out == b"HELLO CONNECT\n", (res, out, err))

    out, err, code = run("-z", "127.0.0.1", port, code=None)
    check("-z closed port exits 1", code == 1, err)
    port, res, t = tcp_server(lambda c: c.recv(10))
    out, err, code = run("-z", "127.0.0.1", port)
    t.join(10)
    check("-z open port exits 0", code == 0, err)

    port = free_port(socket.SOCK_DGRAM)
    srv = ncat("-u", "-l", "127.0.0.1", port, "--recv-only")
    wait_port(port, "udp")
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as u:
        u.sendto(b"udp datagram\n", ("127.0.0.1", port))
    time.sleep(0.5)
    srv.terminate()
    out, err = finish(srv)
    check("UDP listen receives datagram", out == b"udp datagram\n", out + err.encode())

    if socket.has_ipv6 and Path("/proc/net/if_inet6").exists():
        port, res, t = tcp_server(echo_upper, host="::1", family=socket.AF_INET6)
        out, err, _ = run("-6", "::1", port, data=b"v6\n")
        t.join(10)
        check("IPv6 ::1 connect", out == b"V6\n", (out, err))
    else:
        skip("IPv6 ::1 connect", "no IPv6 loopback")

    sock = base / "tmp" / "ncat.sock"
    srv = ncat("-U", "-l", "/tmp/ncat.sock", "--recv-only")
    wait_path(sock)
    with socket.socket(socket.AF_UNIX) as c:
        c.connect(str(sock))
        c.sendall(b"unix\n")
    out, err = finish(srv)
    check("Unix socket listen", out == b"unix\n", out + err.encode())

    port = free_port()
    srv = ncat("-l", "127.0.0.1", port, "--allow", "10.9.9.9")
    wait_port(port)
    with socket.create_connection(("127.0.0.1", port)) as c:
        c.settimeout(5)
        rejected = c.recv(10) == b""
    srv.kill()
    finish(srv)
    check("--allow rejects other addresses", rejected)

    # ---------------- exec：无 shell 环境 ----------------
    port = free_port()
    srv = ncat("-l", "127.0.0.1", port, "-e", "/ncat -h")  # --version 输出到 stderr，-h 输出到 stdout
    wait_port(port)
    with socket.create_connection(("127.0.0.1", port)) as c:
        c.settimeout(10)
        data = recv_all(c)
    finish(srv)
    check("-e runs program directly without /bin/sh", f"Ncat {VERSION} ".encode() in data, data[:200])
    _, err, code = run("-l", "127.0.0.1", free_port(), "-c", "cat", code=None)
    check("-c without /bin/sh fails clearly", code == 2 and "/bin/sh is not executable" in err, err)
    port = free_port()
    srv = ncat("-l", "127.0.0.1", port, "-e", "cat")
    wait_port(port)
    with socket.create_connection(("127.0.0.1", port)) as c:
        c.settimeout(10)
        data = recv_all(c)
    out, err = finish(srv)
    check("-e needs absolute path (PATH not searched)", data == b"", err)

    (base / "upper.lua").write_text(
        "while true do\n  local d = io.stdin:read(1)\n  if d == nil then break end\n"
        "  io.write(d:upper()); io.flush()\nend\n")
    (base / "info.lua").write_text('print(_VERSION .. " " .. tostring(os.getenv("NCAT_REMOTE_ADDR")))\n')
    port = free_port()
    srv = ncat("-l", "127.0.0.1", port, "-k", "--lua-exec", "/upper.lua")
    wait_port(port)
    replies = []
    for word in (b"lua one\n", b"lua two\n"):
        with socket.create_connection(("127.0.0.1", port)) as c:
            c.settimeout(10)
            c.sendall(word)
            c.shutdown(socket.SHUT_WR)
            replies.append(recv_all(c))
    srv.kill()
    finish(srv)
    check("--lua-exec with -k (built-in Lua, no interpreter)", replies == [b"LUA ONE\n", b"LUA TWO\n"], replies)
    port = free_port()
    srv = ncat("-l", "127.0.0.1", port, "--lua-exec", "/info.lua")
    wait_port(port)
    with socket.create_connection(("127.0.0.1", port)) as c:
        c.settimeout(10)
        data = recv_all(c)
    finish(srv)
    check("Lua 5.4 and NCAT_REMOTE_ADDR env", data.strip() == b"Lua 5.4 127.0.0.1", data)

    # ---------------- 代理和名字解析 ----------------
    proxy = free_port()
    srv = ncat("-l", "127.0.0.1", proxy, "--proxy-type", "http", "--proxy-auth", "u:p")
    wait_port(proxy)
    suffix = f":{proxy:04X}"
    bound = [line.split()[1] for table in ("/proc/net/tcp", "/proc/net/tcp6")
             for line in Path(table).read_text().splitlines()[1:]
             if line.split()[1].endswith(suffix) and line.split()[3] == "0A"]
    check("HTTP proxy server listens only on given address (local patch)", bound == [f"0100007F{suffix}"], bound)
    # ncat 代理收到客户端半关闭会关闭整条隧道，客户端用 --no-shutdown 等待回复。
    target, res, t = tcp_server(echo_upper)
    out, err, _ = run("--no-shutdown", "--proxy", f"127.0.0.1:{proxy}", "--proxy-type", "http",
                      "--proxy-auth", "u:p", "127.0.0.1", target, data=b"via http proxy\n")
    t.join(10)
    check("HTTP CONNECT proxy server + client with auth", out == b"VIA HTTP PROXY\n", (out, err))
    _, err, code = run("--proxy", f"127.0.0.1:{proxy}", "--proxy-type", "http", "--proxy-auth", "u:bad",
                       "127.0.0.1", free_port(), code=None)
    check("HTTP proxy rejects wrong credentials", code == 1 and "407" in err, err)
    srv.kill()
    finish(srv)

    def socks5(conn):
        """最小 SOCKS5：无认证、只支持 CONNECT 域名，记录请求的域名，转发到 target。"""
        assert conn.recv(3)[:1] == b"\x05"
        conn.sendall(b"\x05\x00")
        head = conn.recv(4)
        assert head[:2] == b"\x05\x01" and head[3] == 3, head
        name = conn.recv(conn.recv(1)[0])
        conn.recv(2)
        conn.sendall(b"\x05\x00\x00\x01" + bytes(6))
        with socket.create_connection(("127.0.0.1", target)) as up:
            data = conn.recv(65536)
            up.sendall(data)
            up.shutdown(socket.SHUT_WR)
            conn.sendall(recv_all(up))
        return name
    target, res2, t2 = tcp_server(echo_upper)
    sp, res, t = tcp_server(socks5)
    out, err, _ = run("--proxy", f"127.0.0.1:{sp}", "--proxy-type", "socks5", "--proxy-dns", "remote",
                      "intranet.example", target, data=b"via socks5\n")
    t.join(10)
    t2.join(10)
    check("SOCKS5 client, hostname resolved by proxy", res == [b"intranet.example"] and out == b"VIA SOCKS5\n",
          (res, out, err))

    hosts_root = new_root("hosts")
    port, res, t = tcp_server(echo_upper)
    out, err, _ = run("backend.local", port, root=hosts_root, data=b"name\n")
    t.join(10)
    check("hostname from /etc/hosts (musl, no NSS)", out == b"NAME\n", (out, err))
    _, err, code = run("backend.local", port, code=None)
    check("unresolvable name without /etc/hosts fails", code != 0 and "backend.local" in err, err)
    _, err, code = run("localhost", port, code=None)
    check("localhost without /etc/hosts fails (musl has no built-in localhost)",
          code == 2 and "localhost" in err, err)

    # ---------------- SSL ----------------
    pki = work / "pki"
    pki.mkdir()
    (pki / "ext.cnf").write_text("subjectAltName=DNS:localhost,DNS:backend.local,IP:127.0.0.1\n")
    openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "3650", "-subj", "/CN=Test Offline CA",
            "-keyout", "ca.key", "-out", "ca.pem", cwd=pki)
    openssl("req", "-newkey", "rsa:2048", "-nodes", "-subj", "/CN=localhost", "-keyout", "srv.key",
            "-out", "srv.csr", cwd=pki)
    openssl("x509", "-req", "-in", "srv.csr", "-CA", "ca.pem", "-CAkey", "ca.key", "-CAcreateserial",
            "-days", "3650", "-extfile", "ext.cnf", "-out", "srv.pem", cwd=pki)
    ca_hash = subprocess.run(["openssl", "x509", "-hash", "-noout", "-in", pki / "ca.pem"], check=True,
                             capture_output=True, text=True).stdout.strip()
    server_ctx = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    server_ctx.load_cert_chain(pki / "srv.pem", pki / "srv.key")

    port = free_port()
    srv = ncat("-l", "127.0.0.1", port, "--ssl", "--recv-only")
    wait_port(port)
    noverify = ssl._create_unverified_context()
    with socket.create_connection(("127.0.0.1", port)) as raw, noverify.wrap_socket(raw) as c:
        c.sendall(b"tls listen\n")
        tls_version = c.version()
    out, err = finish(srv)
    check("--ssl listen with generated temporary key, no /etc/ssl", out == b"tls listen\n"
          and tls_version == "TLSv1.3", (out, err, tls_version))

    def slow_relay(dst_port):
        """双向中继，客户端到服务端方向按 700 字节小块发送，让服务端反复读到半条 TLS 记录。"""
        lsock = socket.create_server(("127.0.0.1", 0))
        lsock.settimeout(20)

        def pump(src, dst, chunk):
            try:
                while data := src.recv(65536):
                    for i in range(0, len(data), chunk):
                        dst.sendall(data[i:i + chunk])
                        if chunk < 65536:
                            time.sleep(0.0002)
                dst.shutdown(socket.SHUT_WR)
            except OSError:
                pass

        def serve():
            with lsock:
                c, _ = lsock.accept()
                u = socket.create_connection(("127.0.0.1", dst_port))
                u.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                back = threading.Thread(target=pump, args=(u, c, 65536), daemon=True)
                back.start()
                pump(c, u, 700)
                back.join(20)
                c.close()
                u.close()
        threading.Thread(target=serve, daemon=True).start()
        return lsock.getsockname()[1]

    payload = os.urandom(2 * 1024 * 1024)
    for opts in ((), ("--recv-only",)):
        port = free_port()
        # 服务端 stdin 保持打开：stdin 为 /dev/null 时服务端立即半关闭，发送端 ncat 见到 EOF 会提前退出。
        srv = ncat("-l", "127.0.0.1", port, "--ssl", *opts, stdin=subprocess.PIPE)
        wait_port(port)
        relay = slow_relay(port)
        # 发送端也用 ncat（stdin EOF 后关闭连接），与 `ncat --ssl host port < file` 用法相同；
        # 未修复时服务端提前退出，发送端报错，这里只检查接收结果。
        # 边收边读服务端 stdout，否则管道写满后服务端阻塞在写 stdout 上，不再读 socket。
        received = []
        reader = threading.Thread(target=lambda: received.append(srv.stdout.read()), daemon=True)
        reader.start()
        run("--ssl", "127.0.0.1", relay, data=payload, code=None, timeout=60)
        try:
            srv.wait(timeout=30)
        except subprocess.TimeoutExpired:
            srv.kill()
            srv.wait()
        reader.join(10)
        srv.stdin.close()
        out, err = b"".join(received), srv.stderr.read().decode(errors="replace")
        check(f"--ssl listen {' '.join(opts)} receives 2 MiB split into partial TLS records (local patch)",
              srv.returncode == 0 and out == payload, (srv.returncode, len(out), err))

    shutil.copy2(pki / "srv.pem", base / "srv.pem")
    shutil.copy2(pki / "srv.key", base / "srv.key")
    port = free_port()
    srv = ncat("-l", "127.0.0.1", port, "--ssl", "--ssl-cert", "/srv.pem", "--ssl-key", "/srv.key",
               "--recv-only")
    wait_port(port)
    verify = ssl.create_default_context(cafile=pki / "ca.pem")
    with socket.create_connection(("127.0.0.1", port)) as raw, \
            verify.wrap_socket(raw, server_hostname="localhost") as c:
        c.sendall(b"tls cert\n")
    out, err = finish(srv)
    check("--ssl-cert/--ssl-key server verified by client", out == b"tls cert\n", (out, err))

    def ssl_client(name, root, *args, env=None, host="backend.local", ok=True):
        port, res, t = tcp_server(echo_upper, wrap=server_ctx)
        # 证书链不可信：不加 -v 只显示 "Ncat: I/O error."（退出 1），-v 才显示
        # "Certificate verification failed (原因)"；主机名不匹配：显示 "Certificate verification error."（退出 2）。
        out, err, code = run("-v", "--ssl", *args, host, port, root=root, env=env, data=b"tls\n", code=None)
        t.join(10)
        if ok:
            check(name, code == 0 and out == b"TLS\n", (code, out, err))
        else:
            check(name, code != 0 and out == b"" and "Certificate verification " in err, (code, out, err))
        return err

    ssl_client("--ssl client without verify (default), by IP", base, host="127.0.0.1")
    ssl_client("--ssl-verify fails with no trust store", hosts_root, "--ssl-verify", ok=False)
    shutil.copy2(pki / "ca.pem", hosts_root / "ca.pem")
    ssl_client("--ssl-verify --ssl-trustfile, SAN DNS name", hosts_root, "--ssl-verify", "--ssl-trustfile", "/ca.pem")
    ssl_client("--ssl-verify SSL_CERT_FILE env", hosts_root, "--ssl-verify", env={"SSL_CERT_FILE": "/ca.pem"})
    # Ncat 自己的主机名检查只比对 DNS SAN 和 CN，不认 IP SAN：按 IP 连接校验一定失败（上游限制）。
    port, res, t = tcp_server(echo_upper, wrap=server_ctx)
    out, err, code = run("--ssl-verify", "--ssl-trustfile", "/ca.pem", "127.0.0.1", port, root=hosts_root,
                         data=b"tls\n", code=None)
    t.join(10)
    check("--ssl-verify by IP rejected even with IP SAN (upstream limit)",
          code == 2 and out == b"" and "Certificate verification error" in err, (code, out, err))
    ssl_client("--ssl-verify hostname mismatch rejected", hosts_root, "--ssl-verify", "--ssl-trustfile",
               "/ca.pem", host="wrong.local", ok=False)

    # 不带 --ssl-trustfile 时依次查找：OpenSSL 默认路径（Alpine 编译值 /etc/ssl/cert.pem、
    # /etc/ssl/certs/<hash>.0），再加 /usr/share/ncat/ca-bundle.crt。
    layouts = {
        "/etc/ssl/cert.pem (Alpine)": "etc/ssl/cert.pem",
        f"/etc/ssl/certs/{ca_hash}.0 (Debian/Ubuntu hashed dir)": f"etc/ssl/certs/{ca_hash}.0",
        "/usr/share/ncat/ca-bundle.crt": "usr/share/ncat/ca-bundle.crt",
    }
    for label, rel in layouts.items():
        root = new_root("ca-" + rel.replace("/", "_"))
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(pki / "ca.pem", root / rel)
        ssl_client(f"--ssl-verify default trust: {label}", root, "--ssl-verify")
    # RHEL/CentOS：/etc/ssl/certs 是指向 /etc/pki/tls/certs 的链接，里面只有 bundle、没有哈希链接。
    root = new_root("ca-rhel")
    (root / "etc/pki/tls/certs").mkdir(parents=True)
    shutil.copy2(pki / "ca.pem", root / "etc/pki/tls/certs/ca-bundle.crt")
    (root / "etc/ssl").mkdir()
    os.symlink("../pki/tls/certs", root / "etc/ssl/certs")
    ssl_client("--ssl-verify RHEL layout not found by default", root, "--ssl-verify", ok=False)
    ssl_client("--ssl-verify RHEL layout with SSL_CERT_FILE", root, "--ssl-verify",
               env={"SSL_CERT_FILE": "/etc/pki/tls/certs/ca-bundle.crt"})
    bundle_certs = len(ssl.create_default_context(cafile=out_dir / "ca-bundle.crt").get_ca_certs())
    shutil.copy2(out_dir / "ca-bundle.crt", hosts_root / "bundle.crt")
    port, res, t = tcp_server(echo_upper, wrap=server_ctx)
    out, err, code = run("-vvv", "--ssl-verify", "--ssl-trustfile", "/bundle.crt", "backend.local", port,
                         root=hosts_root, data=b"tls\n", code=None)
    t.join(10)
    check(f"shipped ca-bundle.crt ({bundle_certs} CAs) loads; test CA not in it", bundle_certs > 100
          and "Using trusted CA certificates from /bundle.crt" in err and "Unable to load" not in err
          and "Certificate verification failed" in err, err[-500:])

    # 静态 OpenSSL 不能加载 provider 模块；目标机 /etc/ssl/openssl.cnf 激活 legacy 模块时 TLS 不受影响。
    root = new_root("ossl-legacy")
    (root / "etc/ssl").mkdir()
    (root / "etc/ssl/openssl.cnf").write_text(
        "openssl_conf = init\n[init]\nproviders = prov\n[prov]\ndefault = d\nlegacy = l\n"
        "[d]\nactivate = 1\n[l]\nactivate = 1\n")
    port, res, t = tcp_server(echo_upper, wrap=server_ctx)
    out, err, code = run("--ssl", "127.0.0.1", port, root=root, data=b"cnf\n", code=None)
    t.join(10)
    check("openssl.cnf activating unloadable legacy provider: TLS still works", code == 0 and out == b"CNF\n",
          (code, out, err))

    # ---------------- SCTP / vsock ----------------
    try:
        socket.socket(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_SCTP).close()
        have_sctp = True
    except OSError:
        have_sctp = False
    if have_sctp:
        port = free_port()
        srv = ncat("--sctp", "-l", "127.0.0.1", port, "--recv-only")
        time.sleep(0.5)
        out, err, _ = run("--sctp", "127.0.0.1", port, data=b"sctp\n")
        out, err = finish(srv)
        check("SCTP listen + connect", out == b"sctp\n", (out, err))
    else:
        skip("SCTP listen + connect", "kernel has no SCTP")

    # --vsock 下位置参数先当 CID：`-l 4242` 是 CID 4242、端口 31337，端口要用 -p。
    srv = ncat("--vsock", "-l", "-p", "4242", "--recv-only")
    time.sleep(0.5)
    try:
        with socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM) as c:
            c.settimeout(5)
            c.connect((socket.VMADDR_CID_LOCAL, 4242))
            c.sendall(b"vsock\n")
        out, err = finish(srv)
        check("vsock listen via local CID", out == b"vsock\n", (out, err))
    except (OSError, AttributeError) as e:
        srv.kill()
        out, err = finish(srv)
        skip("vsock listen via local CID", f"{e}; ncat: {err.strip()}")
finally:
    shutil.rmtree(work, ignore_errors=True)

print(f"ALL PASS: {count} checks, {len(skipped)} skipped {skipped}", flush=True)
