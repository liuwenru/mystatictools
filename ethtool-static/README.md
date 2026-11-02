# ethtool 7.2 纯静态版

ethtool 7.2（2026-10-19 发布，经 kernel.org 下载目录核实为当前最新版本），
使用 Alpine 3.22 + musl 从源码静态构建，libmnl 静态链接。
支持 Linux x86_64 / aarch64，运行时不需要共享库或动态加载器。

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

```text
dist/
├── x86_64/       # ethtool、ethtool.8、ethtool.bash-completion、COPYING.ethtool、SHA256SUMS
├── aarch64/
├── ethtool-7.2-linux-x86_64-static.tar.gz
└── ethtool-7.2-linux-aarch64-static.tar.gz
```

| 文件 | 说明 |
| --- | --- |
| `ethtool` | 静态二进制，x86_64 约 911 KB，aarch64 约 963 KB |
| `ethtool.8` | 官方手册页，`man ./ethtool.8` |
| `ethtool.bash-completion` | 官方 bash 补全，`source ./ethtool.bash-completion` 或放到 `/usr/share/bash-completion/completions/ethtool` |
| `COPYING.ethtool` | GPL-2.0 |

### 固定版本与校验

| 组件 | 来源 | SHA-256 | 校验依据 |
| --- | --- | --- | --- |
| ethtool-7.2.tar.xz | kernel.org | `44256ddf…6507` | 维护者 Michal Kubecek 的 GPG 签名（`.tar.sign`）验证通过，与 kernel.org `sha256sums.asc` 一致 |

完整哈希见 Dockerfile。libmnl 用 Alpine 的 `libmnl-static`，随 3.22 分支仓库更新，未锁定版本，
本次实际使用 libmnl 1.0.5、gcc 14.2.0、musl 1.2.5。
升级时同步修改 Dockerfile 中的版本和哈希、`build.sh` 中的版本、`test/smoke-test.py` 中的版本断言。

## 编译取舍

上游可选功能全部保留，没有关闭任何功能：

- **netlink 接口（libmnl）**：内核 5.6 起 ethtool 主要通过 netlink 工作，`--json`、`--monitor`、
  PSE/PLCA/MM、模块固件升级等新功能只有 netlink 版本才有。构建时检查 `ETHTOOL_ENABLE_NETLINK`，
  libmnl 缺失会直接构建失败，不会悄悄退化成只有 ioctl 的版本。
- **寄存器/EEPROM/光模块解析（pretty dump）**：`-d` 按驱动解析寄存器（e1000、ixgbe、igb、hns3、
  stmmac、vmxnet3 等），`-m` 解析 SFP/QSFP/CMIS 光模块信息和 DOM 诊断。代码体积是主要来源，保留。
- 保留上游默认编译参数，二进制 strip 过。

## 使用

```sh
./ethtool eth0                    # 速率、双工、自协商、链路状态
./ethtool -i eth0                 # 驱动、固件版本、PCI 地址
./ethtool -S eth0                 # 网卡统计（丢包、错误计数）
./ethtool -k eth0                 # 卸载特性；-K eth0 tso off gro off 修改
./ethtool -g eth0 / -G eth0 rx 4096
./ethtool -l eth0 / -L eth0 combined 8
./ethtool -m eth0                 # 光模块信息和收发光功率
./ethtool -d eth0                 # 寄存器
./ethtool --json -k eth0          # JSON 输出（只有 netlink 实现的子命令支持）
./ethtool --monitor               # 监听网卡配置变化，Ctrl-C 退出
```

## 运行依赖与行为

- **只依赖内核接口**：不读取配置文件和数据文件，不调用外部命令，不需要 `/etc`、terminfo 或证书。
- **权限**：查询大多不需要 root；修改（`-s`、`-K`、`-G`、`-L` 等）需要 `CAP_NET_ADMIN`，
  否则报 `Operation not permitted`。部分驱动的 `-i`、`-d`、`-m`、`-S` 也要求 root。
- **旧内核**：内核不支持 ethtool netlink（5.6 以前）时自动退回 ioctl，基本功能可用；
  这时 `--json`、`--monitor` 等 netlink 专有功能不可用。`--disable-netlink` 可以强制走 ioctl，
  测试用它验证了 ioctl 路径（未在真实旧内核上验证）。
- **网络命名空间**：只能看到当前命名空间的网卡。查看容器里的网卡用 `nsenter -n -t PID ./ethtool ...`
  或 `ip netns exec NAME ./ethtool ...`。
- **网卡和驱动决定能做什么**：虚拟网卡（veth、virtio_net 等）大部分设置会报 `Not supported`，
  这是驱动没有实现，不是静态编译导致的。

## 已知行为（不是静态编译造成的）

- `--json` 只支持部分子命令；对 `-i`、`-S`（不带 `--all-groups`）等 ioctl 子命令会提示不支持。
- `--monitor` 输出到管道或文件时有缓冲，进程被结束时最后一段可能丢失；需要实时看时直接输出到终端。

## 验证

构建阶段必须通过下列检查才导出：

1. `file`、`readelf -h` 架构；`readelf -l` 无 `INTERP`，`readelf -d` 无 `NEEDED`；版本为 7.2；
   `ethtool-config.h` 确认 netlink 和 pretty dump 已启用。
2. 上游 `make check`（`test-cmdline`，命令行解析用例；`test-features` 只在关闭 netlink 时编译，未运行）。
3. `test/smoke-test.py`（构建容器内，没有 `CAP_NET_ADMIN`，只用 `lo`）：版本、帮助、netlink 查询、
   `-k`、`--json -k`、`--disable-netlink`、`-T`、未知网卡和错误参数报错、无权限时 `-K` 被拒绝、
   解析代码已编入、手册页、bash 补全加载。

另外在两台宿主上用 `unshare -n` 新建空网络命名空间运行修改类测试（脚本检测到除 `lo` 外有网卡时拒绝运行，
不会动真实网卡）：

```sh
unshare -n python3 test/smoke-test.py dist/x86_64 --netns
```

用 veth 测试 `-i`、`-S`、`--json`、`-K`（netlink 和 ioctl 两条路径）、`-L/-l`、`--monitor` 收到特性变更通知。
测试主机和结果见 `test/VALIDATION.md`。

## Reference Documentation

- [ethtool 下载页（kernel.org）](https://www.kernel.org/pub/software/network/ethtool/)
- [ethtool git 仓库](https://git.kernel.org/pub/scm/network/ethtool/ethtool.git)
- [ethtool 7.2 NEWS](https://git.kernel.org/pub/scm/network/ethtool/ethtool.git/tree/NEWS?h=v7.2)
- [ethtool 手册页](https://man7.org/linux/man-pages/man8/ethtool.8.html)
- [内核 ethtool netlink 接口文档](https://docs.kernel.org/networking/ethtool-netlink.html)
- [libmnl](https://netfilter.org/projects/libmnl/)
