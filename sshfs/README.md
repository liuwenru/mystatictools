# sshfs 3.7.6 静态构建

面向离线 Linux，Alpine 3.24 + musl 纯静态编译，支持 x86_64 和 aarch64。
sshfs 本身不实现 SSH 协议，运行时 `execvp("ssh")` 调用外部客户端；非 root 挂载还要调用
setuid 的 `fusermount3`。所以把 sshfs、libfuse 工具和 OpenSSH 客户端一起静态编译、一起分发，
目标机不需要安装 fuse3、openssh-client 或任何共享库。

## 目录与产物

```text
Dockerfile            # 下载校验 → 编译 → 无共享库环境检查 → 导出
build.sh              # 构建并导出单个架构（或 all）
test/run-test.sh      # 真实挂载测试入口（宿主执行）
test/client-test.sh   # 在只有静态 busybox + 本包程序的 chroot 中执行的用例
dist/x86_64/          # x86_64 产物
dist/aarch64/         # aarch64 产物
```

每个产物目录：

| 文件 | 来源 | 用途 |
| --- | --- | --- |
| `sshfs` | sshfs 3.7.6 | 主程序，静态链接 libfuse 3.18.3、glib |
| `fusermount3` | libfuse 3.18.3 | 非 root 挂载/卸载，需 setuid root |
| `mount.fuse3` | libfuse 3.18.3 | `mount -t fuse` / fstab 辅助程序 |
| `ssh` `ssh-keygen` `ssh-add` `ssh-agent` `ssh-keyscan` | OpenSSH 10.6p1 | sshfs 调用的客户端及密钥管理 |
| `SHA256SUMS` | | 校验清单 |

全部为 static-pie ELF，无 `INTERP`、无 `NEEDED`。

## 安装

```sh
install -m 0755 sshfs ssh ssh-keygen ssh-add ssh-agent ssh-keyscan mount.fuse3 /usr/local/bin/
install -o root -g root -m 4755 fusermount3 /usr/local/bin/   # 只 root 使用时可不加 setuid
ln -sf /usr/local/bin/sshfs /sbin/mount.fuse.sshfs            # 需要 fstab / mount -t fuse.sshfs 时
ln -sf /usr/local/bin/sshfs /sbin/mount.sshfs
```

- 推荐装在 `/usr/local/bin`：libfuse 编译时固定优先调用 `/usr/local/bin/fusermount3`，找不到再查 PATH。
  如果系统已有发行版的 fusermount3，也能工作，但版本不同。
- sshfs 按 PATH 查找 `ssh`。不放进 PATH 时用 `-o ssh_command=/path/to/ssh`。

使用：

```sh
sshfs user@host:/data /mnt/data -o reconnect,ServerAliveInterval=15
fusermount3 -u /mnt/data          # 或 root: umount /mnt/data
echo 'user@host:/data /mnt/data fuse.sshfs _netdev,IdentityFile=/root/.ssh/id_ed25519 0 0' >> /etc/fstab
```

## 功能取舍

**sshfs 与 libfuse：功能完整保留。** sshfs 没有编译期可选项，所有 `-o` 选项都在
（reconnect、`-C`、`max_conns`、`idmap=user/file`、`password_stdin`、`directport`、`passive`、`vsock` 等）。
libfuse 编入 io_uring 支持（liburing + libnuma 静态库）和内建的 subdir/iconv 模块。
libfuse 的两个路径在编译时写死：

- `fuse.conf` 为 `/etc/fuse.conf`（`--sysconfdir=/etc`），与发行版一致；
- fusermount3 优先路径为 `/usr/local/bin/fusermount3`（由 `--prefix=/usr/local` 决定）。

**OpenSSH 客户端：** 链接 OpenSSL libcrypto（全部常用算法，包括 ML-KEM 混合密钥交换、
Ed25519/ECDSA/RSA）和 zlib（`ssh -C` / `sshfs -C` 压缩）。以下功能不可用：

| 功能 | 原因 | 替代 |
| --- | --- | --- |
| Kerberos/GSSAPI 认证 | 需要 krb5 库、`/etc/krb5.conf` 和 KDC，离线场景很少用 | 密钥或密码认证；配置里的 `GSSAPIAuthentication` 只报 Unsupported 警告 |
| PKCS#11（智能卡/HSM） | 编译了，但要 `dlopen` 厂商 `.so`，musl 静态程序不能 dlopen | 在有动态 ssh 的机器上用 ssh-agent 转发 |
| FIDO/U2F（`sk-*` 硬件密钥） | 同上需 dlopen，且没有构建 ssh-sk-helper；内建方式要 libfido2+libcbor+libudev，服务器上一般没有硬件密钥 | 普通 ed25519 密钥 |
| libedit、ldns | 前者只用于交互式 sftp，后者用于 SSHFP 的 DNSSEC 校验，sshfs 都用不到 | — |
| scp、sftp、sshd、helper 程序 | 不属于 sshfs 运行所需 | 需要时用系统自带的 |

**OpenSSH 不读取 `/etc/ssh/ssh_config`。** 系统配置目录用的是 prefix=/usr/local 时的上游默认值
`/usr/local/etc/ssh`。原因：Fedora/RHEL/Rocky 等的 `/etc/ssh/ssh_config` 通过 crypto-policies
引入了发行版补丁才有的选项（`GSSAPIKexAlgorithms`、`mlkem1024nistp384-sha384`），上游 ssh 读到后报
`Bad configuration option` 并直接退出（已在 Fedora 宿主复现）。`~/.ssh/config` 照常读取。
需要全局配置时写到 `/usr/local/etc/ssh/ssh_config`，全局 known_hosts 为 `/usr/local/etc/ssh/ssh_known_hosts`。

## 运行依赖（纯静态不等于没有运行时依赖）

- **内核 FUSE**：`/dev/fuse` 存在（`modprobe fuse`）。容器中需 `--device /dev/fuse --cap-add SYS_ADMIN`。
- **`/etc/passwd` 中有当前用户**：ssh 启动即调用 `getpwuid()`，找不到就报 `No user exists for uid N`。
  musl 不支持 NSS，**LDAP/SSSD 等只存在于目录服务里的用户无法使用**（musl 只会回退查询 nscd socket）。
- **非 root 使用**：`fusermount3` 须为 root 所有并 setuid；`/etc/mtab` 应为 `/proc/self/mounts` 的链接
  （主流发行版默认如此，缺失时 `fusermount3 -u` 报 `failed to open /etc/mtab`）；`allow_other` 需要在
  `/etc/fuse.conf` 写入 `user_allow_other`。
- **`/proc` 已挂载、`/dev/null` 存在**。
- **`mount.fuse3` 及 fstab 方式**通过 `/bin/sh -c` 启动 sshfs，需要 `/bin/sh`。直接运行 `sshfs` 不需要。
- **名称解析**：musl 只用 `/etc/hosts` 和 `/etc/resolv.conf`，不读 nsswitch.conf（mDNS、systemd-resolved 的
  NSS 插件无效；resolved 的 127.0.0.53 作为 DNS 服务器可以用）。离线环境建议用 IP 或写 hosts。
- 不需要证书、terminfo、OpenSSL 配置或插件。宿主有 `/etc/ssl/openssl.cnf`（Fedora 的 crypto-policies）时
  也已验证不影响 ssh。
- 服务端需要 SFTP 子系统（OpenSSH 默认启用）。

## 构建

需要联网、Docker 和默认 buildx；脚本固定 `--builder default`，不新建或切换 builder：

```sh
./build.sh              # 当前主机架构
./build.sh x86_64       # 或 amd64
./build.sh aarch64      # 或 arm64；建议在 192.168.182.150 原生执行
./build.sh all          # 两种都构建；非本机架构需宿主已配置 QEMU/binfmt，脚本不安装
```

导出会覆盖 `dist/<架构>/`。共享目录下同一架构不要在两台机器上同时构建。

| 组件 | 版本 | 固定方式 |
| --- | --- | --- |
| sshfs | 3.7.6 | SHA256 `6a1bcb31450a077e9cb1b7ff158c71de34db697c3c0da6cb362502131e495893` |
| libfuse | 3.18.3 | SHA256 `bcd19582c5e30f7fe45dd86a5540e998590aa01903afc7ebcbeea6c8ac5421ee` |
| OpenSSH portable | 10.6p1 | SHA256 `a9dc9565dffe8640f64d863cd29a32bc4a3dbdec0566a7fc44c5d6ee767d5f39` |
| Alpine | 3.24 | 镜像标签 |
| OpenSSL 3.5.9、glib 2.88.1、pcre2、zlib、liburing 2.14、numactl 2.0.19 | | 随 Alpine 3.24 仓库更新，未锁定 |

三个源码包的哈希已分别与 GitHub release 的 digest、OpenSSH release notes 公布的 SHA256 核对一致。
当前从上游 URL 下载（curl 重试 5 次），**不是离线构建方案**。

## 测试

```sh
test/run-test.sh dist/x86_64     # 在 x86_64 主机
test/run-test.sh dist/aarch64    # 在 ARM 主机
```

需要 Docker、宿主 `/dev/fuse`，并能从 Alpine 仓库安装测试用的 sshd 和 busybox-static。
脚本只创建本次专用的 Docker 网络和两个容器（名字带 PID），临时目录用 `$TMPDIR`，退出时全部删除。

- 服务端：普通 Alpine 容器跑 sshd（测试夹具，不是本包内容）。
- 客户端：chroot 里只有静态 busybox 和本包程序，没有 `/lib`、没有 libc。chroot 根目录先 bind 成挂载点，
  因为 fusermount3 的 auto_unmount 检查要求 `/` 是挂载点（真实系统都满足）。

用例：密钥认证挂载后的读写、mkdir、rename、symlink、chmod、truncate、16 MiB 文件校验、df；
`-C` + reconnect + max_conns=4 + idmap=user + allow_other；password_stdin；ssh-agent/ssh-add；
`mount.sshfs` 和 `mount.fuse3 'sshfs#...'`；ssh-keyscan；非 root 通过 setuid fusermount3 挂载/卸载；
非 root allow_other（验证读取 `/etc/fuse.conf`）；auto_unmount（kill -9 sshfs 后自动卸载）。
Dockerfile 的 check 阶段另外在无共享库的根文件系统中检查版本、算法列表、三种密钥生成，以及不读取
`/etc/ssh/ssh_config`。

## 验证结果

| 项目 | x86_64 | aarch64 |
| --- | --- | --- |
| 构建主机 | 本机 Fedora 44，原生 | 192.168.182.150，原生 |
| ELF 架构、无 INTERP/NEEDED（readelf） | 通过 | 通过 |
| Dockerfile 无共享库检查 | 通过 | 通过 |
| `test/run-test.sh` 全部用例 | 通过 | 通过 |

另外在 Fedora 宿主上直接运行 x86_64 产物（宿主带 crypto-policies 的 ssh/openssl 配置），只读挂载
ARM 主机目录，读取的文件哈希与本地一致。全部为原生测试，未使用模拟器。

**未验证：** io_uring 通道（要求内核 ≥ 6.14 且 fuse 模块开启 `enable_uring`）、vsock、directport、passive、
idmap=file、iconv 模块、PKCS#11/FIDO、LDAP 用户、老内核（如 3.10/4.x）、长时间断线重连和性能。
除 Fedora 宿主外，没有在其他发行版的真实离线机器上验证。

## Reference Documentation

- [sshfs 发布页](https://github.com/libfuse/sshfs/releases)、源码包内 `sshfs.rst`（选项说明）
- [libfuse 发布页](https://github.com/libfuse/libfuse/releases)、源码包内 `README.md`、`doc/fusermount3.1`、`doc/mount.fuse3.8`
- [OpenSSH portable 下载](https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/)、
  [OpenSSH 10.6 release notes](https://www.openssh.com/txt/release-10.6)、[ssh_config(5)](https://man.openbsd.org/ssh_config)
- [Linux FUSE 文档](https://www.kernel.org/doc/html/latest/filesystems/fuse.html)
- [musl 与 glibc 的功能差异（NSS、DNS）](https://wiki.musl-libc.org/functional-differences-from-glibc.html)
- [Alpine 3.24 软件包](https://pkgs.alpinelinux.org/packages?branch=v3.24)
