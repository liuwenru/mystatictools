# Ncat 7.993 纯静态版

Nmap 项目的 `ncat`，取自 Nmap 7.993 源码包（2026-10-23 发布，经官方下载页和 changelog 核实为当前最新版本）。
用 Alpine 3.22 + musl 构建 Linux x86_64 / aarch64，OpenSSL、Lua 静态编入，运行时不需要共享库或动态加载器。

Ncat 不是 OpenBSD `nc` 或传统 netcat：`-e`、`-c`、`-k`、`-z`、`--ssl`、`--proxy` 等选项按 Ncat 手册，
与其他 nc 的同名参数不完全相同。运行包不提供 `nc` 链接，需要时自行 `ln -s ncat nc`。

## 构建和产物

需要 Docker、默认 buildx，构建需要联网（上游测试步骤断网运行）。默认只构建当前主机架构：

```sh
./build.sh
./build.sh amd64 --progress plain
./build.sh aarch64 --progress plain
./build.sh all             # 仅在已有跨架构执行能力时使用
```

x86_64 在本机原生构建，aarch64 在 `192.168.182.150` 原生构建。
脚本不创建、修改或切换 builder，不安装模拟器。共享目录下不要在两台机器上并发构建同一架构。
编译默认 4 个任务，可用 `--build-arg JOBS=8` 调整。上游测试约需 25 分钟。

```text
dist/
├── x86_64/       # ncat、ncat.1、ca-bundle.crt、LICENSE、SHA256SUMS
├── aarch64/
├── ncat-7.993-linux-x86_64-static.tar.gz
└── ncat-7.993-linux-aarch64-static.tar.gz
```

| 文件 | 说明 |
| --- | --- |
| `ncat` | 约 5.5 MB（x86_64）/ 5.1 MB（aarch64），已 strip |
| `ncat.1` | 手册页，`man ./ncat.1` |
| `ca-bundle.crt` | Ncat 随源码发布的 Mozilla 根证书，`--ssl-verify` 用，见“SSL 证书校验” |
| `LICENSE` | Nmap Public Source License（NPSL） |

### 固定版本与校验

`nmap-7.993.tar.bz2` 的 SHA-256：

```text
270e55f04915bfcecb5db8feb959d4c5ba86a48c094520a4f1c07571e1c79c59
```

与官方 `sigs/nmap-7.993.tar.bz2.digest.txt` 一致，`.asc` 签名用 Nmap Project Signing Key
（`436D 66AB 9A79 8425 FDA0  E3F8 01AF 9F03 6B93 55D0`）验证通过。

Lua 5.4.9、nbase、nsock、libpcap 1.10.7 来自同一源码包。OpenSSL 用 Alpine 的
`openssl-libs-static`，随 3.22 分支仓库更新，未锁定版本；本次实际使用 openssl-libs-static 3.5.9、gcc 14.2.0、musl 1.2.5。
OpenSSL 是静态编进去的，修复其漏洞需要重新构建，替换系统 OpenSSL 没有作用。
升级时修改 Dockerfile 中的版本和 SHA-256、`build.sh` 和 `test/smoke-test.py` 中的版本。

## 编译取舍

- 用 Nmap 顶层 configure 生成 nbase、nsock、ncat 的配置，只执行 `make build-ncat`，
  不编译 nmap、nping、zenmap、ndiff，也不需要 libssh2。
- **启用**：OpenSSL（`--ssl*`）、内置 Lua 5.4（`--lua-exec`）、vsock（`--vsock`）、IPv6、Unix socket、SCTP。
- **libpcap**：nsock 引用了抓包接口，链接时需要，用源码包自带的 1.10.7 静态编入；
  Ncat 本身不抓包，运行时不会打开任何抓包设备。
- `--prefix=/usr`，因此程序内置的证书路径是 `/usr/share/ncat/ca-bundle.crt`。

### 本地补丁

三个补丁都只改一处条件判断，`patches/` 中写明原因；上游 master（2026-11-01 查看）均未修复：

| 补丁 | 问题 | 不打补丁的影响 |
| --- | --- | --- |
| `listen-recv-only-single-socket.patch` | 7.99 起（上游提交 b408fc243c）`--recv-only` 不再监听 stdin，但监听循环仍要求 fd 数大于 1 | 只有一个监听 socket 时 `ncat -l --recv-only` 启动即以 0 退出：指定监听地址、`-4`，或内核禁用 IPv6 的机器上 `ncat -l 8080 --recv-only > file` 收不到任何数据。默认双栈监听时有两个 socket，不受影响，所以上游测试没有发现 |
| `listen-ssl-partial-record.patch` | `-l --ssl` 接收时，`SSL_read` 读到半条 TLS 记录（`WANT_READ`）返回 0，监听循环当作连接结束 | **静默丢数据**：不带 `-k` 时 `ncat -l --ssl > file` 收到前几 KB 就以 0 退出。跨网络时 TLS 记录常被拆成多个 TCP 段，几乎必现：x86_64 → aarch64 发 20 MB 只收到 8–32 KB；Alpine nmap-ncat 7.97 在回环上同样截断。带 `-k` 时不受影响 |
| `proxy-server-listen-address.patch` | `--proxy-type http` 监听模式下不解析位置参数中的地址（7.97、7.92 同样如此） | `ncat -l 127.0.0.1 3128 --proxy-type http` 实际监听 `[::]` 和 `0.0.0.0`，代理对所有网卡开放；`-l` 又不能和 `-s` 同用，没有别的办法限制 |

经代理连接目标（`--proxy`）时目标名字仍交给代理解析，行为不变。代理补丁与上游的差别：
`ncat -l 127.0.0.1 3128 --proxy-type http` 不再接受 `::1` 来的连接（上游测试中有 1 项依赖这一点，见“验证”）；
需要双栈时不写地址，或分别写 `127.0.0.1`、`::1` 启动两个。不需要该补丁时删除 `patches/` 中的文件即可。

## 使用

```sh
./ncat -l 8080                                   # 监听 TCP，收到的数据输出到 stdout
./ncat -lk 8080 > /dev/null                      # -k 保持监听，接受多个连接
./ncat 10.0.0.2 8080 < file                      # 发送文件
./ncat -z -w 3 10.0.0.2 22 && echo open          # 只测试端口是否可连，0 为可连
./ncat -u -l 5140                                # UDP
./ncat -U /run/app.sock                          # Unix socket
./ncat -l 9000 -k -e /bin/cat                    # 每个连接执行一个程序（必须写绝对路径）
./ncat -l 9000 -c 'echo hello; date'             # 通过 /bin/sh 执行
./ncat -l 9000 --lua-exec echo.lua               # 内置 Lua 解释器执行脚本
./ncat --ssl 10.0.0.2 443                        # TLS 客户端，默认不校验证书
./ncat --ssl-trustfile ca.pem app.local 443      # 指定 CA 即开启校验，主机名要与证书 DNS SAN 一致
./ncat -l 8443 --ssl                              # TLS 服务端，自动生成临时 RSA 密钥
./ncat -l 8443 --ssl --ssl-cert srv.pem --ssl-key srv.key
./ncat -l 127.0.0.1 3128 --proxy-type http       # 简易 HTTP 代理（支持 CONNECT），只监听本机
./ncat --proxy 10.0.0.1:1080 --proxy-type socks5 db.local 5432
./ncat -l 9000 --broker                          # 多客户端互相转发
```

## 运行依赖与行为

- **`-c` / `--sh-exec`** 固定调用 `/bin/sh -c`；没有 `/bin/sh` 时启动即报
  `/bin/sh is not executable, so '-c' won't work.`。`-e` / `--exec` 不经过 shell，
  也**不查 PATH**，程序要写绝对路径（写 `-e cat` 会连接后立刻断开）。
- **`--lua-exec`** 使用内置 Lua 5.4，不需要系统 lua。静态程序不能加载 Lua C 模块（`.so`），纯 Lua 模块可以 `require`。
- **名字解析**：musl 解析器只读 `/etc/hosts` 和 `/etc/resolv.conf`，不走 NSS（LDAP/SSSD、mDNS 无效）。
  没有 `/etc/hosts` 时连 `localhost` 也解析不了（glibc 会内置回退，musl 不会），极简容器里用 `127.0.0.1`。
  通过 SOCKS4a/SOCKS5 代理时可用 `--proxy-dns remote` 让代理解析。
- **TLS 收发与 EOF**（上游行为）：服务端收到对端 close_notify 后不会立即结束，要等 TCP 关闭；
  `ncat -l --ssl < /dev/null` 这类 stdin 立即结束的服务端会先半关闭，发送端 ncat 见到 EOF 即退出。
  用 ncat 收文件时服务端 stdin 保持终端或用 `--recv-only`。
- **经 ncat 自己的 HTTP 代理**：客户端 stdin 结束时 ncat 会半关闭连接，ncat 代理随即关闭整条隧道，
  回复收不到；`printf ... | ncat --proxy ...` 这类用法加 `--no-shutdown`。
- **`--ssl` 临时密钥**：服务端不给 `--ssl-cert` 时每次启动生成 2048 位 RSA 自签证书，用内核 `getrandom`，
  不需要 `/dev/urandom` 或证书目录；客户端看到的证书每次不同。
- **OpenSSL legacy provider**：nsock 启动 TLS 时会尝试加载 `legacy` 模块（RC4、DES 等老算法），
  静态程序不能 dlopen 模块，`-vv` 时会显示 `OpenSSL legacy provider failed to load`，不影响 TLS 连接。
- **`/etc/ssl/openssl.cnf`**：静态 OpenSSL 按 Alpine 的编译值读取该文件（`OPENSSL_CONF` 可改）。
  测试过配置中激活 `legacy` 模块的情况：模块加载不了，但 TLS 连接正常。
- **SCTP**（`--sctp`）需要内核 sctp 模块；**vsock**（`--vsock`）需要虚拟化环境的 vsock 驱动。
  vsock 下第一个位置参数是 CID：监听写 `ncat --vsock -l -p 端口`（`-l 4242` 会被当成 CID 4242、端口 31337），
  连接写 `ncat --vsock CID 端口`。
- 不需要 locale、终端定义或其他辅助程序。

## SSL 证书校验

`--ssl` 默认**不校验**服务端证书。`--ssl-verify`（或给了 `--ssl-trustfile`）时：

- 给了 `--ssl-trustfile FILE`：只信任该文件中的 CA，最可靠；
- 没给：信任 OpenSSL 默认位置 + `/usr/share/ncat/ca-bundle.crt`（可把随包的 `ca-bundle.crt` 放到这里）。
  默认位置按 Alpine 编译值是 `/etc/ssl/cert.pem` 和 `/etc/ssl/certs/<hash>.0`，可用环境变量 `SSL_CERT_FILE` 改。

| 目标系统目录布局 | 不加参数能否找到系统 CA |
| --- | --- |
| Debian / Ubuntu：`/etc/ssl/certs` 有哈希链接 | 能 |
| Alpine：`/etc/ssl/cert.pem` | 能 |
| RHEL 系：证书在 `/etc/pki/tls/certs/ca-bundle.crt`，`/etc/ssl/certs` 链接过去但没有哈希文件 | 不能；用 `SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt` 或 `--ssl-trustfile` |

上表按各发行版的目录布局在 chroot 中模拟测试，未在真实 RHEL 上验证；
若目标机另有 `/etc/ssl/cert.pem`，也能直接找到。

主机名校验的限制（上游行为）：

- 只比对证书的 DNS SAN（没有 DNS SAN 时比对 CN），**不认 IP SAN**：按 IP 连接时 `--ssl-verify` 一定失败，
  要用与证书一致的主机名（离线环境写进 `/etc/hosts`）。
- 证书链不可信时只显示 `Ncat: I/O error.`（退出码 1），加 `-v` 才显示 `Certificate verification failed (原因)`；
  主机名不匹配显示 `Certificate verification error.`（退出码 2）。

离线内网一般是自签或内部 CA，直接用 `--ssl-trustfile 内部CA.pem`。

## 许可证

Ncat 随 Nmap 使用 NPSL，不是 GPL：内部运维使用和免费再分发没有问题；把 Ncat 集成进商业产品
对外销售需要 Nmap OEM 授权。详见随包 `LICENSE`。

## 验证

构建阶段必须通过下列检查才导出：

1. configure 检测到 OpenSSL、vsock 头文件，`ncat_lua.o` 已编译，程序内置证书路径为 `/usr/share/ncat/ca-bundle.crt`。
2. 上游 `make -C ncat check`（addrset、URI、命令行拆分、证书通配符匹配）全部通过。
3. 上游 `ncat-test.pl`（414 项外部行为测试，含 13 项上游标记的预期失败）：除下文 2 项外全部通过。
4. `file`、`readelf -h` 检查架构；`readelf -l` 无 `INTERP`，`readelf -d` 无 `NEEDED`；`--version` 为 7.993。
5. `test/smoke-test.py`（47 项）在只含 ncat 的 chroot 中运行（无 `/bin/sh`、共享库、`/etc/ssl`、`/dev`、PATH）：
   - 收发：TCP、UDP、IPv6、Unix socket、SCTP；单个监听 socket 的 `--recv-only`（含 `-k -4`），`-z` 退出码，`--allow`；
   - 执行：`-e` 不经 shell、不查 PATH，`-c` 无 `/bin/sh` 时报错，`--lua-exec` 配合 `-k` 及 `NCAT_REMOTE_ADDR`；
   - 代理和解析：HTTP 代理服务端只监听指定地址、带认证转发、错误口令 407，SOCKS5 由代理解析域名，
     `/etc/hosts`，无 `/etc/hosts` 时 `localhost` 解析失败；
   - TLS：经小块转发的中继发送 2 MiB，服务端（带/不带 `--recv-only`）完整接收（未打补丁时收到 0 字节）；临时密钥（TLS 1.3）、`--ssl-cert/--ssl-key`，`--ssl-verify` 的信任来源（trustfile、`SSL_CERT_FILE`、
     `/etc/ssl/cert.pem`、哈希目录、`/usr/share/ncat/ca-bundle.crt`、RHEL 布局找不到），无信任、主机名不匹配、
     按 IP 连接均拒绝，随包 `ca-bundle.crt` 可加载，`openssl.cnf` 激活 legacy 模块时 TLS 正常；
   - vsock：Docker 默认 seccomp 不允许 AF_VSOCK（EPERM），构建中跳过，在宿主上单独验证监听。

上游测试的处理（只改测试环境，不为测试改程序）：

- 断网运行：构建网络的 DNS 如果对任意名字都返回地址（代理软件的 fake-IP 模式），addrset 中
  “非法地址应解析失败”的 20 项会误报。断网后 `/etc/hosts` 只读，3 项 `scanme.nmap.org` 名字解析用例改用 `localhost`。
- 源码包中的 `test-cert.pem` 已于 2026-08-30 过期，测试前重新生成。
- 用 `setsid` 启动 `ncat-test.pl`：脚本用 `kill -$$` 结束子进程，perl 不是进程组组长时会一直等待。
- 允许失败 2 项，其余失败都会中止构建：
  - `Server UNIX socket listen on ncat.unixsock --udp (DGRAM)`：客户端读到 stdin EOF 后立即删除自己的源 socket，
    服务端随后 connect 回去报 `No such file or directory`。Alpine 的 nmap-ncat 7.97、Fedora 44 的
    nmap-ncat 7.92（glibc）同样 5/5、3/3 失败，属于上游行为；客户端保持 stdin 打开时收发正常。
  - `HTTP CONNECT IPv6 client, IPv4 server`：用例以 `ncat 127.0.0.1 端口 -l --proxy-type http` 启动代理，
    再从 `::1` 连接，依赖监听地址被忽略这一缺陷。未打 `proxy-server-listen-address.patch` 时该项通过，
    打补丁后代理只监听 127.0.0.1，按预期连不上。

测试主机和结果见 `test/VALIDATION.md`。

## Reference Documentation

- [Ncat 主页](https://nmap.org/ncat/)
- [Ncat 用户指南](https://nmap.org/ncat/guide/)
- [ncat(1) 手册页](https://nmap.org/book/ncat-man.html)
- [Nmap 下载页及签名校验说明](https://nmap.org/download.html)
- [Nmap 源码包与签名](https://nmap.org/dist/)
- [Nmap CHANGELOG](https://nmap.org/changelog.html)
- [Nmap Public Source License](https://nmap.org/npsl/)
- [OpenSSL 证书默认路径与 SSL_CERT_FILE](https://docs.openssl.org/3.5/man3/SSL_CTX_load_verify_locations/)
- [musl 与 glibc 的差异](https://wiki.musl-libc.org/functional-differences-from-glibc.html)
