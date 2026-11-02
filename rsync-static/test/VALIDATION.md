# rsync 3.5.1 静态版验证记录

日期：2026-11-02。

| 架构 | 构建主机 | 方式 | rsync |
| --- | --- | --- | --- |
| x86_64 | 本机（x86_64，Fedora 44 宿主，内核 7.2.9） | Alpine 3.22 容器原生构建及测试 | 6,943,040 字节 |
| aarch64 | 192.168.182.150（aarch64，Fedora 44，内核 7.2.9） | Alpine 3.22 容器原生构建及测试 | 6,449,128 字节 |

两端均使用默认 buildx，未使用 QEMU，未安装或修改模拟器及 builder。
共享目录为 `/root/workspace/mystatictools`，两种架构分别在各自主机构建、分别导出到 `dist/x86_64`、`dist/aarch64`，
同一架构没有在两台机器上同时构建。

## 结果

- 版本：`rsync  version 3.5.1  protocol version 33`。
  - Optimizations：`no SIMD-roll, no asm-roll, openssl-crypto, no asm-MD5`
  - Checksum list：`xxh128 xxh3 xxh64 (xxhash) md5 md4 sha1 none`
  - Compress list：`zstd lz4 zlibx zlib none`
  - Daemon auth list：`sha512 sha256 sha1 md5 md4`
- ELF Machine 分别为 X86-64 / AArch64；`readelf -l` 均无 INTERP，`readelf -d` 均无 NEEDED。
- 上游测试（构建容器内，`--network=none`），两种架构结果相同：

  | 运行方式 | 通过 | 跳过 | 失败 |
  | --- | --- | --- | --- |
  | 默认 | 298 | 60 | 0 |
  | `--protocol=30` | 297 | 61 | 0 |
  | `--protocol=29` | 292 | 66 | 0 |
  | `--use-tcp --daemon-tests-only` | 147 | 13 | 0 |

- `smoke-test.py`：两种架构 112 项全部 PASS，0 SKIP。
- 宿主直接运行 `test/host-check.sh`（不经容器，`env -i`）：两台主机各 15 项全部通过。
  对端为系统 rsync `3.5.1-g315819c5`（glibc，协议 33）和发布目录中的旧 rsync 3.1.2（协议 31，
  x86_64 为 glibc 动态链接、aarch64 为 static-pie，不支持 ACL/xattr，因此只比较内容、链接和硬链接；复制到临时目录使用，未改动原文件）。
- Debian 最小容器（`timberio/vector:0.61.0-debian`，`--network none`，无系统 rsync）：静态版守护进程在模块
  未写 `gid =` 时客户端收到 `@ERROR: invalid gid nobody`（退出码 5），写 `gid = nogroup` 后上传成功，文件属主 65534。
- 没有 ssh 时：`Failed to exec ssh: No such file or directory (2)`，退出码 14。

## 构建过程中查明的问题

- musl iconv 对 GBK/GB18030/BIG5 只能解码不能编码（`iconv_open("GBK","UTF-8")` 失败），rsync `--iconv` 会直接退出，
  因此改为静态链接 GNU libiconv 1.19.1。
- 构建机 DNS（192.168.188.8）对任意域名（包括 `.invalid`）返回 `198.18.x.x` 地址，宿主 glibc 同样解析成功，
  导致 `daemon-deny-dns-failopen` 失败；测试改为 `--network=none` 后通过，rsync 本身行为正确。
- `daemon-auth-group` 失败原因是 Alpine 的 `/etc/group` 把 root 列为 daemon 组成员，root 先命中读写规则；
  rsync 行为正确，构建容器内调整组成员后通过。
- x86_64 滚动校验 SIMD 无法启用：Alpine GCC（musl 目标）不支持函数多版本，最小示例编译即报
  `use of multiversioned function without a default`。

## 二进制 SHA-256

```text
a03830377a7a6cc77c81924ff8fadb279b50c29d99b42a0b5a0b335b39ab88b6  x86_64/rsync
d45b23a21570f9549e6ad432a19370d95cbf07ff333e42bbefec710d342cdcfa  aarch64/rsync
```

## 未验证

- 低于 6.13 的内核、没有挂载 `/proc` 的环境（本构建不使用 `*xattrat`，ACL 一律走 `/proc/self/fd`，构建容器中已覆盖该路径）。
- 真实 ssh 远程主机（测试用模拟 ssh 的脚本）、SELinux 环境、LDAP/SSSD 用户名映射。
