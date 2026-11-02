# pstree 23.7 + procs 0.14.12 验证记录

日期：2026-10-31。

| 架构 | 构建主机 | 方式 | pstree 大小 | procs 大小 |
| --- | --- | --- | --- | --- |
| x86_64 | 本机（x86_64，Fedora 44 宿主，内核 7.2.9） | Alpine 3.22 容器原生构建及测试 | 496,008 字节 | 6,811,024 字节 |
| aarch64 | 192.168.182.150 | Alpine 3.22 容器原生构建及测试 | 517,640 字节 | 6,167,592 字节 |

两端均使用默认 buildx，未使用 QEMU，未安装或修改模拟器及 builder。
共享目录为 `/root/workspace/mystatictools`，两种架构先后构建、分别导出，没有互相覆盖。

## 结果

- pstree 版本 23.7，procs 版本 0.14.12；ELF Machine 分别为 X86-64 / AArch64。
- 四个二进制 `readelf -l` 均无 INTERP，`readelf -d` 均无 NEEDED
  （x86_64 procs 为 static-pie，有动态节但只用于自身重定位）。
- 两个 procs 与官方 zip 中的文件逐字节相同（`cmp`）。
- 两种架构 `smoke-test.py` 45 项全部 PASS，无 SKIP；测试前已删除构建容器内全部 terminfo 数据库。
- 宿主直接运行：本机 `env -i dist/x86_64/pstree -p 1`；192.168.182.150 上
  `env -i dist/aarch64/pstree -A 1`、`procs --version`、`procs sshd`，输出正常。
- 两个运行包只含 pstree、pstree.1、COPYING.psmisc、procs、LICENSE.procs、SHA256SUMS，`sha256sum -c` 通过。

## 二进制 SHA-256

```text
dbea584fdd78059d4f8fb4e1bfa49766968a025d78323685dda1ebb5391d53ff  x86_64/pstree
87b6c533c287f361bc55b1d2e1cf8195a6ec6b6bc91faa9437785a28c13a8273  aarch64/pstree
9be54e40394bd35d7fb46d7f1069b71069c395953dcd10380cfe9f5657a1274a  x86_64/procs
bd09e92e5ff1cf32d9695997c4841e3c4e2a2c565f8584a1cc15d998b531fa4c  aarch64/procs
```

## 测试环境限制

- pstree/procs 需要真实 `/proc`，构建容器内无法在 chroot 中挂载 procfs，
  因此测试没有在 chroot 中进行，而是以空环境变量直接运行；静态链接由 readelf 检查保证。
- `-Z` 在构建容器中只验证了输出格式（读取 `/proc/PID/attr/current`），没有真实 SELinux/AppArmor 标签。
- `-S`、`-N` 只验证能运行，构建容器内无法创建新的命名空间来检查命名空间变化的显示。

## 未验证

- 启用 SELinux 或 AppArmor 的系统上 `-Z` 的实际标签。
- procs 的 Docker 列（构建环境没有 docker.sock）。
- procs 在不应答终端查询的控制台（串口等）上的表现：本机伪终端测试中，
  不加 `--theme` 时 procs 等待超过 20 秒仍未输出，已在 README 说明；未在真实串口验证。
- procs 交互式分页器（less/more/内置）的按键操作。
- 用户实际离线目标机器、旧内核。
