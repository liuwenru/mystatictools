# iperf3 3.22 纯静态版

基于 ESnet 官方 iperf 3.22（2026-09-29 发布，经官方发布页核实为当前最新版本），
使用 Alpine 3.22 + musl 构建 Linux x86_64 / aarch64 的 `iperf3`。
musl、OpenSSL（RSA 认证）、lksctp-tools（SCTP）全部静态链接，
运行时不需要安装共享库或动态加载器。

3.22 修复了多个安全问题（服务端 use-after-free、`iperf_auth.c` 堆溢出、
DoS 死循环等，见官方 RELNOTES），服务端对外开放时不要使用旧版本。

## 构建和产物

需要 Docker、默认 buildx，构建需要联网。默认只构建当前主机架构：

```sh
./build.sh
./build.sh amd64 --progress plain
./build.sh aarch64 --progress plain
./build.sh all             # 仅在已有跨架构执行能力时使用
```

x86_64 在本机原生构建，aarch64 在 `192.168.182.150` 原生构建。
脚本不创建、修改或切换 builder，不安装模拟器。共享目录下不要在两台机器上并发构建同一架构。
编译默认 4 个任务，可用 `--build-arg JOBS=8` 调整。

```text
dist/
├── x86_64/                # iperf3、iperf3.1 手册页、LICENSE、SHA256SUMS
├── aarch64/
├── iperf3-3.22-linux-x86_64-static.tar.gz
└── iperf3-3.22-linux-aarch64-static.tar.gz
```

运行包只有二进制、手册页（`man ./iperf3.1` 可查看）、BSD 许可证和校验文件，不含测试资料。

固定源码 `iperf-3.22.tar.gz`，SHA-256 与 GitHub 发布资产 digest 及
`downloads.es.net` 上的 `.sha256` 文件一致：

```text
1c0d0fb02c52626111d6e132db80edfbf27bbaff8bd9245df2a371dcb0b35a92
```

Alpine 依赖随 3.22 分支仓库更新，未锁定版本。本次构建实际使用：gcc 14.2.0、
musl 1.2.5、openssl-libs-static 3.5.9、lksctp-tools-static 1.0.19。
OpenSSL 是静态编进去的，修复其漏洞需要重新构建 iperf3，替换系统 OpenSSL 没有作用。
升级 iperf 需同时修改 Dockerfile 中的版本和 SHA-256，以及 `build.sh` 中的版本、
`test/smoke-test.py` 中的版本断言。

## 使用

```sh
./iperf3 -s                                   # 服务端，默认 TCP 5201
./iperf3 -s -1 -p 5301                        # 只接受一次测试后退出
./iperf3 -c 10.0.0.2 -t 10 -P 4               # TCP，4 条并行流
./iperf3 -c 10.0.0.2 -R                       # 反向：服务端发送
./iperf3 -c 10.0.0.2 --bidir
./iperf3 -c 10.0.0.2 -u -b 500M               # UDP 必须指定带宽，默认只有 1 Mbit/s
./iperf3 -c 10.0.0.2 -J > result.json         # JSON 输出
./iperf3 -c 10.0.0.2 --sctp                   # 需要内核 SCTP 支持
```

需要在防火墙放行服务端端口：TCP 控制连接 + 测试数据所用协议（TCP/UDP/SCTP）同一端口。

RSA 认证（iperf3 不生成密钥，需在别的机器用 openssl 生成后拷过来）：

```sh
openssl genrsa -out private.pem 2048
openssl rsa -in private.pem -pubout -out public.pem
printf 'mario,%s\n' "$(printf '{mario}luigi' | sha256sum | cut -d' ' -f1)" > users.csv

./iperf3 -s --rsa-private-key-path private.pem --authorized-users-path users.csv
IPERF3_PASSWORD=luigi ./iperf3 -c 10.0.0.2 --username mario --rsa-public-key-path public.pem
```

不设置 `IPERF3_PASSWORD` 时会在终端交互输入密码。认证只保护“谁能发起测试”，
测试数据本身不加密。

## 功能与取舍

官方 configure 的可选功能全部启用，没有为构建关闭任何功能。`iperf3 --version` 显示：

```text
CPU affinity setting, IPv6 flow label, SCTP, TCP congestion algorithm setting,
sendfile / zerocopy, socket pacing, authentication, bind to device,
support IPv4 don't fragment, POSIX threads, GSO/GRO support
```

- 使用官方 `--enable-static-bin`，未修改上游源码。
- 不安装 `libiperf` 静态库和头文件，只交付命令行工具。
- 这些功能编译进来了，但能否使用取决于目标机内核和权限，不是二进制能解决的：
  - `--sctp`：需要内核 SCTP 模块（`modprobe sctp`），很多发行版默认不加载或被禁用。
  - `-C 算法`：算法需在内核中存在；非 root 只能用
    `net.ipv4.tcp_allowed_congestion_control` 中的算法（`reno`、`cubic` 一般都可用）。
  - `--bind-dev`：使用 `SO_BINDTODEVICE`，5.7 以下内核需要 root 或 `CAP_NET_RAW`。
  - `--fq-rate`：需要网卡使用 `fq` 队列规则。
  - `--gsro`（GSO/GRO）：需要较新的内核 UDP GSO/GRO 支持。
  - `-A` CPU 亲和、`--flowlabel`、`--dscp` 等依赖对应内核接口。

## 运行依赖

纯静态不等于没有运行时依赖：

- **可写临时目录**：每条测试流都会用 `mkstemp` 建一个临时文件作为发送缓冲区，
  默认在 `/tmp`，依次读取 `TMPDIR`、`TEMP`、`TMP`，也可用 `--tmp-template` 指定。
  `/tmp` 不可写会导致测试直接失败（报 `unable to create a new stream`）。
- **`/dev/urandom`**：生成缓冲区随机数据、测试 UUID、认证相关随机数。
- **主机名解析**：静态 musl 自带解析器，只读取 `/etc/hosts` 和 `/etc/resolv.conf`，
  不走 glibc NSS（`nsswitch.conf`、LDAP/SSSD、mDNS 等都不会生效）。
  离线环境建议直接用 IP，或写入 `/etc/hosts`。
- **交互输入密码**需要 `/dev/tty`；无终端时用 `IPERF3_PASSWORD`。
- 不需要证书文件、插件、shell 或其他辅助程序。

## 验证

构建阶段必须通过下列检查才导出：

1. 官方 configure 检测到 OpenSSL（`HAVE_SSL`）和 SCTP（`HAVE_SCTP_H`），否则失败。
2. 上游 `make check`（t_timer、t_units、t_uuid、t_api、t_auth）全部通过。
3. `file`、`readelf -h` 检查架构；`readelf -l` 无 `INTERP`，`readelf -d` 无 `NEEDED`。
4. `--version` 为 3.22，且包含 SCTP 和 authentication。
5. `test/smoke-test.py` 在只含二进制的 chroot 中启动服务端和客户端（无共享库、
   shell、openssl），校验 JSON 结果：TCP、`/etc/hosts` 主机名、反向、双向、
   4 流并行、`-Z` 零拷贝、`-C reno`、MSS/窗口/omit、UDP 正反向、
   连接拒绝报错、RSA 认证正确/错误密码、IPv6、SCTP，以及 `/tmp` 无残留临时文件。
   测试中的 `/dev/null`、`/dev/urandom` 是普通文件替代品，不能用于生产。

测试主机和结果见 `test/VALIDATION.md`。

## Reference Documentation

- [官方 3.22 发布页](https://github.com/esnet/iperf/releases/tag/3.22)
- [官方源码及 SHA-256](https://downloads.es.net/pub/iperf/)
- [iperf3 官方文档](https://software.es.net/iperf/)
- [命令行参数说明 invoking](https://software.es.net/iperf/invoking.html)
- [构建说明（含 --enable-static-bin）](https://software.es.net/iperf/building.html)
- [3.22 Release Notes](https://github.com/esnet/iperf/blob/3.22/RELNOTES.md)
- [官方许可证（BSD）](https://github.com/esnet/iperf/blob/3.22/LICENSE)
