# GNU tar 1.35 + bsdtar/bsdunzip 3.8.11 验证记录

日期：2026-10-31。

| 架构 | 构建主机 | 方式 | tar | bsdtar | bsdunzip |
| --- | --- | --- | --- | --- | --- |
| x86_64 | 本机（x86_64，Fedora 44 宿主，内核 7.2.9） | Alpine 3.22 容器原生构建及测试 | 808,672 字节 | 7,115,232 字节 | 4,885,984 字节 |
| aarch64 | 192.168.182.150（aarch64，Fedora 44，内核 7.2.9） | Alpine 3.22 容器原生构建及测试 | 865,680 字节 | 6,633,800 字节 | 4,404,488 字节 |

两端均使用默认 buildx，未使用 QEMU，未安装或修改模拟器及 builder。
共享目录为 `/root/workspace/mystatictools`，两种架构先后构建、分别导出，没有互相覆盖。

## 结果

- 版本：`tar (GNU tar) 1.35`；`bsdtar 3.8.11 - libarchive 3.8.11 zlib/1.3.2 liblzma/5.8.4 bz2lib/1.0.8
  liblz4/1.10.0 libzstd/1.5.7 liblzo2/2.10 libxml2/2.13.9 openssl/3.5.9 libb2/bundled libacl/2.3.2`。
- `bsdunzip 3.8.11 - libarchive 3.8.11`，链接库与 bsdtar 相同。
- ELF Machine 分别为 X86-64 / AArch64；六个二进制 `readelf -l` 均无 INTERP，`readelf -d` 均无 NEEDED。
- 两种架构结果相同：
  - GNU tar 上游测试：排除 xattr03 后 222 通过、21 跳过、0 失败。
  - libarchive 上游测试：libarchive_test、bsdtar_test、bsdunzip_test 通过，0 失败。
  - `smoke-test.py`：165 项全部 PASS，0 SKIP（xattr、ACL、chattr 属性在构建容器内均可测）。
- 宿主直接运行（`env -i`，不经容器）：
  - 本机：x86_64 的 tar、bsdtar 均能保存/还原 `trusted.*` xattr（文件和目录），bsdtar 能读取 GNU tar 写入的
    `trusted.*`；`--xattrs-include='trusted*'` 正确过滤掉 `user.*`。
  - 192.168.182.150：aarch64 的 tar、bsdtar 版本正确，`trusted.*` 互通，`bsdtar --zstd` 创建和列出正常。
  - 两台主机：`bsdunzip -P` 解开本机 bsdtar 生成的 AES-256 zip。
- 两个运行包只含 tar、tar.1、COPYING.tar、bsdtar、bsdtar.1、bsdunzip、bsdunzip.1、COPYING.libarchive、SHA256SUMS，
  `sha256sum -c` 通过。
- 加入 bsdunzip 后重新构建，tar、bsdtar 的 SHA-256 与前一次构建相同。

## 二进制 SHA-256

```text
a35cdd0ae2542b6480d94b9bb31dc0835e9a0b2212fe3b525f821cf7ec277c49  x86_64/tar
ad4c9cc3c2c20d71784e980886be368e2bce14a1d1a413cfdb8831a0cc2c8f6f  x86_64/bsdtar
3a84e6eeb656c1c4a765d9ff092243fcfd986cc070902f18b712f28c39f282d1  x86_64/bsdunzip
355ee2a306544d48eba68f4cce8b1223ace60b3d715b5642adc9b295b3266d87  aarch64/tar
b6146e452bd5ad0969c04a6e872d86c8354b730f16fa1dd3d288e4516833ffc6  aarch64/bsdtar
535a78aec062ad0555f4996e084cc0abc50d7621938b91a8b26c6e9491ba479e  aarch64/bsdunzip
```

## 构建中发现并处理的问题

- tar 1.35 的 `src/Makefile`、`tests/Makefile` 漏写 `$(LIBINTL)`，静态链接 GNU libintl 缺符号：configure 加 `LIBS=-lintl`。
- libarchive 的 `--enable-bsdtar=static` 产物仍有 9 个 NEEDED：make 时改用 `LDFLAGS=-all-static`。
- 缺 `linux-headers` 时 libarchive 不支持 chattr 属性：已加入构建依赖，并检查 `HAVE_WORKING_FS_IOC_GETFLAGS`。
- libarchive 测试在 `/tmp` 留下超长路径目录，buildkit 导出时报 file name too long：测试后用 Python rmtree 清理。
- GNU tar 解 bsdtar 归档时目录 mtime 被后续成员改写：上游已有的行为，用 Alpine tar 1.35 + bsdtar 3.8.10 复现，
  需加 `--delay-directory-restore`，已写入 README。
- bsdunzip 的 `-I CP936` 在 musl 下报 `Cannot handle CP936`（GBK/GB18030 可用）；libarchive 的字符集转换
  由 bsdtar 共用，不为此打补丁，README 说明改用 `-I GBK`。

## 测试环境限制

- `trusted.*` 只能在宿主 root 下测试（docker build 没有 CAP_SYS_ADMIN），因此宿主测试只覆盖 xattr 和版本，
  完整 smoke 测试在构建容器内运行。
- `--selinux` 只验证选项可用；构建容器和两台宿主都没有用 SELinux 标签做还原测试。
- 远程归档只验证 tar 调用 `/usr/bin/ssh backup.example /usr/sbin/rmt`（用假 ssh 记录参数），未连接真实远端 rmt。

## 未验证

- 启用 SELinux 的系统上 `--selinux` 的实际标签保存和还原。
- 真实 ssh + 远端 rmt 的远程归档、磁带设备、多卷归档在真实设备上的使用。
- 用户实际离线目标机器、旧内核；没有 `/bin/sh` 的极简环境下 GNU tar 压缩报错的具体表现。
