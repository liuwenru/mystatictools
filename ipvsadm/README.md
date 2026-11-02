# ipvsadm 1.31 静态构建

面向离线 Linux，使用 Alpine 3.20 + musl 构建，保留 popt 参数解析与
libnl Generic Netlink 支持。本次仅整理工程、修正构建检查并验证已有产物，未升级或重新编译。

## 目录

```text
build.sh                 # 构建并导出单个架构
Dockerfile               # 依赖、编译、运行镜像
src/                     # 原始源码压缩包与 SHA256SUMS
dist/amd64/              # 原 x86_64 产物
dist/arm64/              # 原 aarch64 产物
test/                    # 测试脚本；临时状态不写入工程
```

每个产物目录包含 `ipvsadm`、`ipvsadm-save`、`ipvsadm-restore` 和 `SHA256SUMS`。
原 `bin_7.1.3-200.fc44.{x86_64,aarch64}` 已分别移动到上述目录，三个文件内容不变。
旧目录名是构建时的宿主内核版本，不是工具版本，也不表示必须使用相同内核。
修改前的 build.sh、Dockerfile 保留为根目录隐藏时间戳备份，不参与 Docker 构建。

## 构建

需要联网、Docker 和默认 buildx，脚本不新建或切换 builder：

```sh
./build.sh                         # 当前主机架构
./build.sh linux/amd64
./build.sh linux/arm64 ipvsadm:arm64
# 也接受 amd64/x86_64、arm64/aarch64
```

导出固定到 `dist/amd64` 或 `dist/arm64`，不再使用 `KVER`。
会覆盖该架构已有产物，不要并发构建同一架构；构建前自行保留需要的历史产物。
ARM 构建优先在 `192.168.182.150` 原生执行，先确认架构、共享绝对路径与默认 builder。
跨架构构建需要主机已配置可用的 binfmt/QEMU，脚本不会安装模拟器。

Dockerfile 固定版本与源码 SHA256：

| 依赖 | 版本 | SHA256 |
| --- | --- | --- |
| ipvsadm | 1.31 | `7276bcf214f31051188b2e44f11029e57303f37e54126e517000c1b2123a6d4e` |
| libnl | 3.7.0 | `9fe43ccbeeea72c653bdcf8c93332583135cda46a79507bfd0a483bb57f65939` |
| popt | 1.19 | `6eb40d650526cb9fe63eb4415bcecdf9cf306f7556e77eff689abc5a44670060` |

`src/` 保存相同源码供审计和重建参考；当前 Dockerfile 仍从固定上游 URL 下载并校验，
**不是离线构建方案**。Alpine 标签和 apk 包随 3.20 仓库更新，未锁定全部传递依赖。
保留原编译功能选项；修正原先对两个 Bash 脚本执行 ldd 的错误检查，
改为检查核心 ELF 的 INTERP/NEEDED 和辅助脚本语法，运行镜像补充 Bash。

## 离线运行与限制

- `ipvsadm` 是纯静态 ELF，无需共享库、证书、插件或额外数据文件。
- 仍需 Linux 内核启用 IPVS、相应调度器及转发功能，以及 root/所需网络管理权限。
  模块不在包内；建议预先由管理员加载。初始化失败时上游程序会尝试调用外部 modprobe。
- `--version` 和 `--help` 也先初始化内核 IPVS，不能在不支持 IPVS 的系统上仅凭它们验证程序。
- 尽量使用数字地址与端口（`-n`）；使用名字时仍依赖系统名称解析配置及服务。
- `ipvsadm-save/restore` 是原版 **Bash 脚本，不是静态二进制**。
  需要 `/bin/bash`、PATH 中的 `ipvsadm`；restore 使用 grep，save 的帮助分支使用 basename。
  脚本自行固定 PATH，不会自动查找同目录的 ipvsadm。
- 无辅助环境时可直接用核心程序 `ipvsadm -S -n` 保存、`ipvsadm -R` 恢复。
  `-R` 本身不清空旧规则；原版 restore 脚本会先执行 `-C`，会删除当前命名空间的所有旧规则。
- 本包不含内核模块、系统服务或防火墙配置。不要在生产命名空间直接试跑清空/恢复测试。

## 测试

在本工具目录执行：

```sh
python3 test/build-layout-test.py
python3 test/smoke-test.py --static-only
sudo python3 test/smoke-test.py
```

静态测试需要 Python 3、binutils/readelf、sha256sum 和 Bash。
完整测试另需 root、unshare/chroot、iproute2、ldd、grep、basename 和可用的内核 IPVS/rr。
功能测试强制新建网络命名空间，失败则报错，绝不回退到宿主网络；在其中设置回环及测试网段路由。
临时目录优先位于 `/tmp/opencode`，退出时清除；测试资料不进入 dist。

验证分层：

1. 两种架构：源码与产物 SHA256、ELF 架构、无 INTERP/NEEDED；辅助脚本与源码逐字节一致及 Bash 语法检查。
2. 本机架构：只有核心二进制的最小 chroot 中验证版本、帮助、服务/后端增删、保存/清空/恢复往返。
3. 随后仅在测试 chroot 加入宿主 Bash/工具及其共享库，验证原版辅助脚本往返、注释过滤和清空旧规则。
4. mock Docker 验证构建脚本的平台参数、导出路径、校验清单和默认 builder；**不等于真实镜像构建验证**。

本轮结果：x86_64 主机原生完整通过；ARM64 静态检查通过。
已有 QEMU 运行 ARM64 时 IPVS 初始化报 `Protocol not available`，未完成 ARM 功能验证，
不能据此判断 ARM 产物有问题。尚未在 ARM 主机执行、未重建 Docker 镜像、未验证真实转发流量与性能。

## Reference Documentation

- [ipvsadm 官方发布目录](https://www.kernel.org/pub/linux/utils/kernel/ipvsadm/)
- [ipvsadm 上游源码仓库](https://git.kernel.org/pub/scm/utils/kernel/ipvsadm/ipvsadm.git/)
- [内核 IPVS 参数与功能依赖](https://www.kernel.org/doc/html/latest/networking/ipvs-sysctl.html)
- [libnl 3.7.0](https://github.com/thom311/libnl/releases/tag/libnl3_7_0)
- [popt 1.19](https://github.com/rpm-software-management/popt/tree/popt-1.19-release)
- 本地 `src/ipvsadm.tar.gz` 中的 README、ipvsadm.8、ipvsadm-save、ipvsadm-restore。
