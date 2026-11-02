# 3.22 验证记录

日期：2026-10-30。

| 架构 | 构建主机 | 方式 | iperf3 大小 |
| --- | --- | --- | --- |
| x86_64 | 本机（x86_64，Fedora 44 宿主，内核 7.2.9） | Alpine 3.22 容器原生构建及 chroot 测试 | 4,414,208 字节 |
| aarch64 | 192.168.182.150 | Alpine 3.22 容器原生构建及 chroot 测试 | 4,010,672 字节 |

两端均使用默认 buildx，未使用 QEMU，未安装或修改模拟器及 builder。
共享目录为 `/root/workspace/mystatictools`，两种架构先后构建、分别导出，没有互相覆盖。

## 结果

- 版本 3.22，ELF Machine 分别为 X86-64 / AArch64。
- `file` 显示 statically linked；`readelf -l` 无 INTERP，`readelf -d` 无动态节。
- 两种架构上游 `make check` 5 项全部通过。
- 两种架构 `smoke-test.py` 全部 PASS，没有 SKIP（构建环境内核可用 IPv6 回环和 SCTP）。
- 跨主机实测：192.168.182.150 运行 aarch64 运行包中的 `iperf3 -s -1`，
  本机 x86_64 产物 `-c -t 3 -P 2`，千兆链路约 940 Mbit/s，结果正常。
- 两个运行包只含 iperf3、iperf3.1、LICENSE、SHA256SUMS，`sha256sum -c` 通过。

## 二进制 SHA-256

```text
b2258871e36fed7635ceb38812ebd4dc44b293fd14b595a0f88c2210517a3551  x86_64/iperf3
d5af6a0413bc2a19df71a3e7d1b6fb284fb9c1a3391efcaf5108817269fc69be  aarch64/iperf3
```

## 未验证

- `--bind-dev`、`-A`、`--fq-rate`、`--gsro`、`--flowlabel`、`--dscp`、`-D` 守护进程模式。
- 交互式输入密码（只测了 `IPERF3_PASSWORD`）。
- 通过 `/etc/resolv.conf` 的 DNS 解析（只测了 `/etc/hosts`）。
- 旧内核、用户实际离线目标机器、高速网卡（10G 以上）下的性能表现。
