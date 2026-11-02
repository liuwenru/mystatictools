# rsync 3.5.1 纯静态版

- rsync 3.5.1（2026-09-21 发布，经 GitHub RsyncProject/rsync Releases 核实为当前最新稳定版），协议版本 33。
- Alpine 3.22 + musl 从源码静态构建，支持 Linux x86_64 / aarch64，运行时不需要共享库或动态加载器。
- 本地复制、远程 shell（ssh）、守护进程（`rsync://`）三种用法都可用；ACL、xattr、xxhash/zstd/lz4、
  `--iconv`、IDN 域名全部编译在内。

## 构建和产物

需要 Docker、默认 buildx，构建需要联网（下载源码和 Alpine 包），测试阶段断网运行。默认只构建当前主机架构：

```sh
./build.sh
./build.sh amd64 --progress plain
./build.sh aarch64 --progress plain
./build.sh all             # 仅在已有跨架构执行能力时使用
```

x86_64 在本机原生构建，aarch64 在 `192.168.182.150` 原生构建。脚本不创建、修改或切换 builder，
不安装模拟器。共享目录下不要在两台机器上并发构建同一架构。构建时完整运行上游测试套件四遍，
单架构约 12 分钟。

```text
dist/
├── x86_64/       # rsync、rsync.1、rsyncd.conf.5、COPYING、SHA256SUMS
├── aarch64/
├── rsync-3.5.1-linux-x86_64-static.tar.gz
└── rsync-3.5.1-linux-aarch64-static.tar.gz
```

| 文件 | x86_64 | aarch64 | 说明 |
| --- | --- | --- | --- |
| `rsync` | 约 6.9 MB | 约 6.4 MB | 已 strip，内含 OpenSSL、GNU libiconv、libidn2 等全部库 |
| `rsync.1` / `rsyncd.conf.5` | | | 官方手册页，`man ./rsync.1` |
| `COPYING` | | | GPL-3.0 |

### 固定版本与校验

| 组件 | 来源 | SHA-256 | 校验依据 |
| --- | --- | --- | --- |
| rsync-3.5.1.tar.gz | GitHub Releases | `c55f9c9d…7bef` | GPG 签名通过，签名子密钥 `8EDF88F4…2C52EC2D`（主密钥 `C0E10545…2EFBCF5D`，Zen Dodd）。3.5.1 的 NEWS 写明 Zen Dodd 获得发布权限，该版本也由其账号 `steadytao` 在官方仓库发布 |
| xxHash v0.8.3（GitHub 源码包） | GitHub tag | `aae608df…9a80` | 上游不签名；sha512 与 Alpine 3.22 aports 的 APKBUILD 一致 |
| libiconv-1.19.1.tar.gz | ftp.gnu.org | `9a068448…edab` | GNU keyring 中维护者 Bruno Haible（`E0FFBD97…1BBEAC08`）的 GPG 签名通过 |

完整哈希见 Dockerfile。Alpine 静态库随 3.22 分支仓库更新，未锁定版本，本次实际使用：
gcc 14.2.0、musl 1.2.5、linux-headers 6.14.2、acl 2.3.2、popt 1.19、zstd 1.5.7、lz4 1.10.0、OpenSSL 3.5.9、
libidn2 2.3.7、libunistring 1.3。
升级时同步修改 Dockerfile 中的版本和哈希、`build.sh` 中的版本、`test/smoke-test.py` 中的版本断言。

## 编译取舍

- **ACL、xattr**：静态链接 libacl；xattr 用 libc 的系统调用。ACL 写入走 3.5.0 新增的
  “先用 `O_NOFOLLOW` 打开再设置”方式（`ACL-at`），在 Linux 上通过 `/proc/self/fd` 实现。
  没有使用 Linux 6.13 新增的 `setxattrat` 等系统调用：musl 1.2.5 没有这些调用号，configure 不启用；
  也不手工补，因为 rsync 只在内核返回 ENOSYS 时回退，而旧版 Docker 等容器的 seccomp 对未知调用
  返回 EPERM，会被误判为可用，导致 ACL 全部设置失败。影响：只有在 6.13+ 内核且没有挂载 `/proc`
  的环境中，ACL 设置会退回按路径设置（上游文档记录的同一退化行为）。
- **校验和压缩**：xxhash（xxh128/xxh3/xxh64）、zstd、lz4 全部启用；zlib 用 rsync 自带的版本（上游默认），
  保证 `-z` 与旧版本兼容。xxhash 在 Alpine 没有静态库，从源码构建 0.8.3（与 Alpine 包同版本）。
- **OpenSSL（3.5.x 静态）**：用于 MD4/MD5 加速和 sha1/sha256/sha512（守护进程认证、`--checksum-choice=sha1`）。
  configure 指定 `--with-openssl-conf=/dev/null`：**不读取目标机的 `/etc/ssl/openssl.cnf`**。
  静态 OpenSSL 无法加载目标机配置引用的 provider 模块（如 RHEL crypto-policies、FIPS 模块），
  不读取可避免因目标机配置导致的不可预期行为；MD4 等 legacy 摘要由 rsync 内置实现，结果相同。
  如确需指定配置，设置环境变量 `OPENSSL_CONF`，rsync 不会覆盖它。
- **`--iconv` 使用静态链接的 GNU libiconv 1.19.1**，不用 musl 的 iconv：musl 1.2.5 对 GBK/GB18030/BIG5
  只能解码不能编码，而 rsync 启动时同时打开两个方向，遇到这些编码直接报
  `iconv_open("GBK", "UTF-8") failed` 并退出。GNU libiconv 的转换表编译在库内，不依赖 gconv 等外部数据文件。
- **IDN 域名**：静态链接 libidn2（+ libunistring），`rsync://例子.测试/` 自动转为 Punycode
  （`xn--fsqu00a.xn--0zwm56d`）；守护进程的 `hosts allow/deny` 也可写中文域名。
- **x86_64 没有滚动校验 SIMD 优化**：上游用 GCC 函数多版本（IFUNC 运行时选择 SSE2/AVX2）实现，
  musl 工具链不支持 IFUNC，configure 自动关闭。只影响增量传输时弱校验的 CPU 速度，结果相同
  （未做性能对比）。MD5 汇编优化在启用 OpenSSL 时上游默认关闭，MD5 走 OpenSSL 的汇编实现。
- 默认远程 shell 为 `ssh`，守护进程配置文件 `/etc/rsyncd.conf`，默认非特权用户/组为 `nobody`/`nobody`，
  均为上游默认值。
- 不打包 `rrsync`（需要 python3）和 `rsync-ssl`（需要 bash 及 openssl/stunnel 等程序）两个脚本：
  它们不是二进制，依赖目标机解释器；需要时从同版本源码包的 `support/` 和根目录取用。

## 使用

```sh
./rsync -aHAX --numeric-ids /data/ /backup/data/          # 本地，保留硬链接、ACL、xattr
./rsync -az --info=progress2 /data/ host:/backup/data/    # 经 ssh，目标机也需要 rsync
./rsync -az --rsync-path=/opt/bin/rsync /data/ host:/data/  # 目标机 rsync 不在 PATH 时
./rsync -a --delete --backup --backup-dir=/backup/old /src/ /dst/
./rsync -a --link-dest=/backup/2026-11-01 /data/ /backup/2026-11-02/   # 硬链接增量备份
./rsync -az --compress-choice=zstd /data/ host:/data/
./rsync --iconv=UTF-8,GBK -a /data/ host:/gbk-data/      # 本机 UTF-8，对端 GBK 文件名

./rsync --daemon --config=/etc/rsyncd.conf                # 守护进程，默认端口 873
./rsync rsync://host/                                     # 列出模块
```

## 运行依赖与行为

- **远程 shell 需要目标机的 ssh**：经 `host:/path` 传输时 rsync 执行 `ssh`（或 `-e` 指定的程序），
  本包不带 ssh。没有 ssh 时报 `Failed to exec ssh: No such file or directory`，退出码 14。
  对端同样需要 rsync，可把本二进制复制过去并用 `--rsync-path` 指定。
- **用户名/组名只读 `/etc/passwd`、`/etc/group`**，不走 NSS。LDAP/SSSD 用户按名称映射时找不到，
  按数字 ID 处理（相当于 `--numeric-ids`）；守护进程的 `uid =`/`gid =`、`auth users = @组` 也只能用
  本地文件中存在的用户和组。
- **默认组 `nobody`**：守护进程以 root 运行、模块未写 `gid =` 时切换到组 `nobody`。Debian/Ubuntu 上该组
  叫 `nogroup`，没有 `nobody` 组，客户端会收到 `@ERROR: invalid gid nobody`（退出码 5）；
  在 rsyncd.conf 中写 `gid = nogroup` 即可。RHEL/Alpine/SUSE 上有 `nobody` 组，不受影响。
- **DNS**：musl 的解析器只读 `/etc/hosts` 和 `/etc/resolv.conf`，不支持 `nsswitch.conf`、mDNS 等。
- **字符编码**：`--iconv` 支持 GNU libiconv 的全部编码（GBK、GB18030、BIG5、Shift_JIS 等），不需要目标机
  locale 文件；本机和对端各自转换自己一侧，对端是 glibc 版 rsync 也可以。
  IDN 转换在未设置 `LANG` 时同样可用（命令行主机名按 UTF-8 处理）。
- **ACL 安全设置需要 `/proc`**：见“编译取舍”；没有 `/proc` 时 ACL 仍可用，只是退回按路径设置。
- **`--info=stats3` 不显示内存分配统计**：依赖 glibc 的 `mallinfo`，musl 没有；其他统计正常。

## 已知行为（不是静态编译造成的）

- **软链接、FIFO、设备文件的纳秒 mtime**：源文件 mtime 与目标创建时间落在同一秒时，rsync 有时不设置这些条目
  的 mtime，目标保留创建时间。用 Fedora 系统 rsync 3.5.1（glibc）和 Alpine rsync 3.5.0 都能复现；普通文件不受影响。
- **守护进程 `use chroot = no` 时默认 `munge symlinks = yes`**：上传的软链接目标前会加 `/rsyncd-munged/`，
  这是上游的安全设计；需要原样保存软链接时在模块里写 `munge symlinks = no`（仅限可信客户端）。
- **`--info=progress2` 的百分比**按预估总量计算，传完可能停在 99%，以 `to-chk=0/N` 为准。

## 验证

构建阶段必须通过下列检查才导出（`--network=none` 断网运行）：

1. **上游测试套件，按上游 CI 跑四遍**：默认、`--protocol=30`、`--protocol=29`、`--use-tcp`（真实 TCP 守护进程）。
   两种架构结果相同，均 0 失败：298 / 297 / 292 / 147 通过，其余由测试自行跳过（需要 ASan、旧版本对端、
   非 root 权限等）。排除 2 项不适用的测试：`fake-super-backup-fifo-regression`（靠 `LD_PRELOAD` 注入故障，
   静态二进制不加载）、`misc-coverage`（要求 `mallinfo` 内存统计）。`daemon-auth-group` 假设 Debian 的组布局，
   构建容器内把 root 移出 `daemon` 组后按原意执行并通过。
2. configure 宏检查（ACL、xattr、xxhash、zstd、lz4、OpenSSL、IDN、iconv、IPv6），链接后确认使用 GNU libiconv；
   ELF 架构、`readelf -l` 无 `INTERP`、`readelf -d` 无 `NEEDED`；版本 3.5.1、协议 33。
3. `test/smoke-test.py`（112 项，rsync 以 `PATH=/nonexistent` 运行）：
   - 本地及远程 shell `-aHAXS --numeric-ids`：属主、setuid、纳秒 mtime、软/硬链接、FIFO、设备、稀疏文件、长路径、
     UTF-8 名称、user xattr、ACL（含默认 ACL）完全一致；
   - xxh128/xxh3/xxh64/md5/md4/sha1 的增量传输（只传改动块）和 `-c`；zstd/lz4/zlibx/zlib 压缩；
   - `--delete --backup --link-dest --exclude --files-from --list-only -n --inplace --append-verify
     --remove-source-files --chown --usermap/--groupmap --info=progress2,stats3`、批处理模式；
   - 守护进程：列模块、拉取、只读模块拒绝上传、密码认证与错误密码（退出码 5）、chroot 下以 nobody 写入、
     `hosts deny` 写无法解析的主机名时拒绝连接、IPv6 `[::1]`；
   - 与 Alpine rsync 3.5.0（协议 32）的远程 shell 和守护进程双向互通；
   - `--iconv` 对 GBK、GB18030、BIG5、Shift_JIS 双向转换；IDN 转 Punycode（有无 `LANG` 两种）；
   - `/etc/ssl/openssl.cnf` 为只加载 null provider 的配置时 sha1/md5/md4 仍正常，`OPENSSL_CONF` 环境变量仍生效；
   - 没有 ssh 时报错退出。
4. 宿主机直接运行（`test/host-check.sh`，15 项，两台主机均通过）：宿主文件系统上的 ACL、`user.*`/`trusted.*`
   xattr；与系统 rsync 3.5.1（glibc，协议 33）及旧 rsync 3.1.2（协议 31）的远程 shell 三个方向、守护进程两个方向互通；
   静态版与 glibc 版 rsync 之间 GBK 文件名三个方向转换。

测试主机和结果见 `test/VALIDATION.md`。未验证：低于 6.13 的内核（两台主机均为 7.2.9，ACL 的 `/proc/self/fd`
路径在构建容器内已覆盖）、真实 ssh 远程主机、SELinux 环境、LDAP/SSSD 用户名映射。

## Reference Documentation

- [rsync 主页](https://rsync.samba.org/)
- [rsync GitHub](https://github.com/RsyncProject/rsync)
- [rsync 3.5.1 发布页](https://github.com/RsyncProject/rsync/releases/tag/v3.5.1)
- [rsync 3.5.1 NEWS](https://github.com/RsyncProject/rsync/blob/v3.5.1/NEWS.md)
- [rsync 手册](https://download.samba.org/pub/rsync/rsync.1)
- [rsyncd.conf 手册](https://download.samba.org/pub/rsync/rsyncd.conf.5)
- [INSTALL.md（依赖库说明）](https://github.com/RsyncProject/rsync/blob/v3.5.1/INSTALL.md)
- [xxHash](https://github.com/Cyan4973/xxHash)
- [GNU libiconv](https://www.gnu.org/software/libiconv/)
- [musl 与 glibc 的功能差异](https://wiki.musl-libc.org/functional-differences-from-glibc.html)
