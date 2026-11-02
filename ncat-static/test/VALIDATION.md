# Ncat 7.993 验证记录

日期：2026-11-01。

| 架构 | 构建主机 | 方式 | ncat 大小 |
| --- | --- | --- | --- |
| x86_64 | 本机（x86_64，Fedora 44 宿主，内核 7.2.9） | Alpine 3.22 容器原生构建及测试 | 5,711,048 字节 |
| aarch64 | 192.168.182.150（aarch64） | Alpine 3.22 容器原生构建及测试 | 5,270,560 字节 |

两端均使用默认 buildx，未使用 QEMU，未安装或修改模拟器及 builder。
共享目录为 `/root/workspace/mystatictools`，两种架构分别导出到 `dist/x86_64`、`dist/aarch64`，没有互相覆盖。
依赖实际版本：openssl-libs-static 3.5.9、gcc 14.2.0、musl 1.2.5；Lua 5.4.9、libpcap 1.10.7 来自 Nmap 源码包。

## 结果

- `Ncat: Version 7.993`，ELF Machine 分别为 X86-64 / AArch64；`readelf -l` 无 INTERP，`readelf -d` 无动态节。
- 两种架构结果相同：
  - 上游 `make -C ncat check`：All tests passed（addrset 中 3 项 scanme.nmap.org 改为 localhost，见 README）。
  - 上游 `ncat-test.pl`：414 项，13 项上游预期失败（XFAIL），2 项允许的失败（Unix DGRAM 上游行为、
    代理补丁使 `HTTP CONNECT IPv6 client, IPv4 server` 按预期失败），其余全部通过。
  - `smoke-test.py`：47 项 PASS，1 项 SKIP（vsock：Docker seccomp 拒绝 AF_VSOCK，EPERM）。
- 宿主直接运行（`env -i`，不经容器）：
  - 两台主机 `--version` 正常；`ncat --vsock -l -p 4242` 在两台主机上均能监听（`ss --vsock` 可见）。
    本机内核有 vmci 传输，未加载 vsock_loopback，未做 vsock 收发。
  - 跨主机 TLS（临时密钥）传输 20,000,000 字节随机数据，SHA-256 一致：
    x86_64 发 → aarch64 `-l -4 --ssl`（stdin 保持打开）、aarch64 `-l -4 --ssl --recv-only`；
    aarch64 发 → x86_64 `-l -4 --ssl --recv-only`。接收端退出码均为 0。
  - 补丁前的同一测试：aarch64 接收端只收到 8,192–32,768 字节即以 0 退出（Fedora 7.92 客户端发送同样如此）。
  - 跨主机普通 TCP 传输 20 MB：补丁前即正常。
- 两个运行包只含 ncat、ncat.1、ca-bundle.crt、LICENSE、SHA256SUMS，`sha256sum -c` 通过。

## 二进制 SHA-256

```text
dffb58f62bacac7cd676fc5cac46cd26d8f8656070e93e5939f868fe2c3cfb34  x86_64/ncat
01fe7221fb176b8bfd4afded30d6fb0faa33a593c9c7bef18a4c7d4e4fd71b74  aarch64/ncat
```

## 构建和测试中发现并处理的问题

- 构建网络 DNS（192.168.188.8）对任意名字返回 198.18.x.x 假地址，addrset 20 项误报：测试步骤 `--network=none`。
- `ncat-test.pl` 用 `kill -$$` 结束子进程，perl 在容器中不是进程组组长时卡死：用 `setsid` 启动。
- 源码包 `test-cert.pem` 已过期：测试前重新生成。
- 上游缺陷，打本地补丁（详见 README“本地补丁”）：
  - 单个监听 socket 时 `-l --recv-only` 立即退出（7.99 起）。
  - `-l --ssl` 读到半条 TLS 记录时误判连接结束，静默截断数据（7.97 已存在）。
  - `-l 地址 --proxy-type http` 忽略监听地址，代理对所有网卡开放（7.97、7.92 已存在）。
- 上游行为，只写入 README：`-c` 依赖 `/bin/sh`；`-e` 不查 PATH；无 `/etc/hosts` 时 `localhost` 解析失败；
  `--ssl-verify` 不认 IP SAN、证书链失败不加 `-v` 只显示 I/O error；RHEL 目录布局下找不到系统 CA；
  vsock 位置参数先当 CID；经 ncat HTTP 代理时客户端半关闭会关闭隧道；HTTP 代理 `-l` 不能和 `-s` 同用。

## 未验证

- 真实 RHEL/麒麟等目标机上的系统 CA 查找（只按目录布局在 chroot 中模拟）。
- vsock 实际收发（需要虚拟机与宿主之间，或加载 vsock_loopback）。
- SCTP 跨主机（只在构建容器回环上测试）。
- 用户实际离线目标机器、旧内核。
