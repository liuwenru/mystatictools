# 2.3.2 验证记录

日期：2026-10-31。

| 架构 | 构建主机 | 方式 | tree 大小 |
| --- | --- | --- | --- |
| x86_64 | 本机（x86_64，Fedora 44 宿主，内核 7.2.9） | Alpine 3.22 容器原生构建及 chroot 测试 | 138,648 字节 |
| aarch64 | 192.168.182.150 | Alpine 3.22 容器原生构建及 chroot 测试 | 200,160 字节 |

两端均使用默认 buildx，未使用 QEMU，未安装或修改模拟器及 builder。
共享目录为 `/root/workspace/mystatictools`，两种架构先后构建、分别导出，没有互相覆盖。

## 结果

- 版本 2.3.2，ELF Machine 分别为 X86-64 / AArch64。
- `file` 显示 statically linked；`readelf -l` 无 INTERP，`readelf -d` 无动态节。
- 编译无警告（上游 Makefile 自带 `-Wall -Wextra -Wconversion` 等）。
- 两种架构容器内 `smoke-test.py` 全部 PASS。x86_64 容器内 `--selinux` 标签写入被拒绝（EPERM），
  该项 SKIP；随后在本机宿主（tmpfs）上对导出的 `dist/x86_64/tree` 重跑完整测试，包括 `--selinux` 在内全部 PASS。
  aarch64 容器内无 SKIP。
- aarch64 产物在 192.168.182.150 宿主上用 `env -i` 直接运行 `--version`、`--du -h /etc` 正常。
- 与宿主 glibc 编译的同一 2.3.2 源码对比：C、C.UTF-8 下 22 组选项输出逐字节相同；
  en_US.UTF-8、zh_CN.UTF-8 下只有排序顺序不同（musl `strcoll` 按字节比较）。
- 两个运行包只含 tree、tree.1、global_info、LICENSE、SHA256SUMS，`sha256sum -c` 通过。

## 二进制 SHA-256

```text
d8e6daa46f589db87691b1a7bca1e83db9709ab983b73872035a883e02ce49b2  x86_64/tree
1b6d6d1e46358fa2016abd431c774833e9d42ad38d87bad9e89cb51f9b091b4c  aarch64/tree
```

## 未验证

- 启用 SELinux 的真实系统上的 `--selinux`（只测了手工写入的 `security.selinux` xattr）。
- 真实 `setfacl` 设置的 ACL（测试用 Python 写入同格式的 `system.posix_acl_access`）。
- 超大目录树（百万级文件）的耗时和内存。
- 交互终端下的颜色显示效果（只校验了转义序列）。
- 用户实际离线目标机器、旧内核。
