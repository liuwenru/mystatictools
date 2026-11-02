# ethtool 7.2 验证记录

日期：2026-10-31。

| 架构 | 构建主机 | 方式 | 大小 |
| --- | --- | --- | --- |
| x86_64 | 本机（x86_64，Fedora 44 宿主，内核 7.2.9） | Alpine 3.22 容器原生构建及测试 | 933,280 字节 |
| aarch64 | 192.168.182.150（aarch64，Fedora 44，内核 7.2.9） | Alpine 3.22 容器原生构建及测试 | 986,376 字节 |

两端均使用默认 buildx，未使用 QEMU，未安装或修改模拟器及 builder。
共享目录为 `/root/workspace/mystatictools`，两种架构分别在各自主机构建、导出到各自目录，没有互相覆盖。

## 结果

- 版本 7.2；ELF Machine 分别为 X86-64 / AArch64；`readelf -l` 无 INTERP，`readelf -d` 无 NEEDED。
- 两种架构上游 `make check`（test-cmdline）通过。
- 构建容器内 `smoke-test.py` 13 项全部 PASS，无 SKIP。
- 两台宿主上 `unshare -n python3 test/smoke-test.py dist/<arch> --netns` 10 项全部 PASS（veth）。
- 宿主真实网卡只读查询（不修改设置）：
  - 本机 vmxnet3 网卡 ens192：`ethtool`、`-i`、`-S`、`-g` 正常，`-d` 输出按 vmxnet3 解析的寄存器，
    说明 pretty dump 代码实际可用。
  - 192.168.182.150 virtio_net 网卡 enp4s0：`ethtool`、`-i` 正常（`env -i` 空环境运行）。
- 运行包只含 ethtool、ethtool.8、ethtool.bash-completion、COPYING.ethtool、SHA256SUMS，`sha256sum -c` 通过。

## 二进制 SHA-256

```text
a6bac088a0a1d9ba756831cbf9376f091d15aa7df21558b0424629d67d885df4  x86_64/ethtool
6083160a32545d8a8fe380e718020966382453bd66b897b6f27b78083de8a6ee  aarch64/ethtool
```

## 测试环境限制

- 构建容器没有 `CAP_NET_ADMIN`，修改类测试放在宿主新建的网络命名空间里，用 veth 进行。
  veth 不支持速率/双工设置、环形缓冲区、寄存器、模块 EEPROM 等，这些在测试中只能确认报 `Not supported`。
- 旧内核只用 `--disable-netlink` 模拟了 ioctl 路径，测试主机内核为 7.2.9。

## 未验证

- 物理网卡上的 `-s`（速率/双工/自协商）、`-G`、`-A`、`-C`、`-p` 闪灯、`-t` 自检、Wake-on-LAN 等修改操作。
- `-m` 光模块解析（没有带光模块的网卡）。
- 除 vmxnet3 以外驱动的 `-d` 寄存器解析。
- 内核 5.6 以前的真实旧内核，以及用户实际离线目标机器。
