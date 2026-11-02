# GNU tar 1.35 + bsdtar/bsdunzip 3.8.11 纯静态版

- `tar`：GNU tar 1.35（2023-07-18 发布，经 ftp.gnu.org 核实为当前最新版本）。
  参数与各发行版默认 tar 完全一致。
- `bsdtar`：libarchive 3.8.11（2026-10-30 发布，经 GitHub Releases 和 libarchive.org 核实为当前稳定版）。
  压缩库和格式全部编译在二进制内，不依赖任何外部程序。
- `bsdunzip`：同一 libarchive 3.8.11 中的 unzip 实现，常用参数与 Info-ZIP unzip 兼容，支持 AES 加密和
  zstd/xz/lzma/bzip2 压缩的 zip。参数和输出完全一致的 Info-ZIP unzip 见同仓库 `unzip-static`。

两者都用 Alpine 3.22 + musl 从源码静态构建，支持 Linux x86_64 / aarch64，
运行时不需要共享库或动态加载器。

**怎么选**：日常打包、解包、增量备份用 `tar`，用法与系统 tar 相同；
目标机没有 xz、zstd 等压缩程序，或者要处理 zip、7z、cpio、iso 时用 `bsdtar`。

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
构建时会完整运行两个项目的上游测试套件，单架构约 8 分钟。

```text
dist/
├── x86_64/       # tar、tar.1、COPYING.tar、bsdtar、bsdtar.1、bsdunzip、bsdunzip.1、COPYING.libarchive、SHA256SUMS
├── aarch64/
├── tar-1.35-bsdtar-3.8.11-linux-x86_64-static.tar.gz
└── tar-1.35-bsdtar-3.8.11-linux-aarch64-static.tar.gz
```

| 文件 | x86_64 | aarch64 | 说明 |
| --- | --- | --- | --- |
| `tar` | 约 790 KB | 约 845 KB | GNU tar |
| `bsdtar` | 约 6.8 MB | 约 6.3 MB | 内含 OpenSSL、libxml2 和全部压缩库 |
| `bsdunzip` | 约 4.7 MB | 约 4.2 MB | 与 bsdtar 链接同一套库 |
| `tar.1` / `bsdtar.1` / `bsdunzip.1` | | | 官方手册页，`man ./tar.1` |
| `COPYING.tar` / `COPYING.libarchive` | | | GPL-3.0 / BSD-2-Clause |

### 固定版本与校验

| 组件 | 来源 | SHA-256 | 校验依据 |
| --- | --- | --- | --- |
| tar-1.35.tar.xz | ftp.gnu.org | `4d62ff37…dc16` | GNU keyring 中维护者 Sergey Poznyakoff 的 GPG 签名通过 |
| libarchive-3.8.11.tar.xz | GitHub Releases | `a3dc0872…43d2` | 维护者 Martin Matuska（`659C84C0…D63D2B36`）的 GPG 签名通过 |

完整哈希见 Dockerfile。Alpine 静态库随 3.22 分支仓库更新，未锁定版本，本次实际使用：
gcc 14.2.0、musl 1.2.5、acl 2.3.2、libselinux 3.6、gettext 0.24.1、zlib 1.3.2、xz 5.8.4、
bzip2 1.0.8、zstd 1.5.7、lz4 1.10.0、lzo 2.10、libxml2 2.13.9、OpenSSL 3.5.9。
升级时同步修改 Dockerfile 中的版本和哈希、`build.sh` 中的版本、`test/smoke-test.py` 中的版本断言。

## GNU tar 编译取舍

- **ACL、xattr、SELinux 全部启用**：静态链接 libacl、libselinux。`--acls`、`--xattrs`、`--selinux`
  可用；在未启用 SELinux 的系统上 `--selinux` 不报错，只是没有标签可存。
- **启用 NLS（静态 GNU libintl）**：翻译目录为 `/usr/share/locale`，与发行版一致。
  目标机装有 tar 的翻译（`tar.mo`）时显示中文提示，没有就显示英文，不影响功能。运行包不带 `.mo`。
  tar 1.35 的 Makefile 漏写了 `$(LIBINTL)`，glibc 上不受影响，静态链接 GNU libintl 时缺符号，
  因此 configure 时加 `LIBS=-lintl`，不修改源码。
- **远程归档（`host:/path/file.tar`）默认用 `/usr/bin/ssh`**，与 Fedora/RHEL 一致；不设置时
  tar 遇到 `host:file` 会直接报 I/O error。远端执行的程序为 `/usr/sbin/rmt`（Debian/RHEL 的位置），
  本包不提供 rmt。文件名含冒号但不是远程路径时加 `--force-local`。
- 保留上游默认编译参数，二进制已 strip。

## bsdtar 编译取舍

- **压缩全部内置**：gzip、bzip2、xz、lzma、zstd、lz4、lzop、lzip、compress(.Z) 读写都不调用外部程序，
  解包时按内容自动识别。
- **格式**：读写 tar（gnu/pax/ustar）、zip（含 AES 加密）、7z、cpio、iso9660、xar、ar、mtree，
  写 shar；只读 rar/rar5、cab、lha、warc 等。
- **OpenSSL 3.5.9**：用于 zip AES 加解密、mtree/xar 的摘要；不同时启用 nettle/mbedtls。
- **libxml2**：用于 xar 格式；不启用 expat（二选一）。
- **libb2 不链接**：Alpine 没有它的静态库，用 libarchive 自带的 BLAKE2s 实现（只用于 RAR5 校验），功能相同。
- ACL（libacl）、xattr、chattr 文件属性（`--fflags`）都启用；构建时检查对应的 configure 宏，缺一项就失败。
- 打包 `bsdtar` 和 `bsdunzip`；不打包 bsdcpio/bsdcat：bsdtar 本身已能读写 cpio 和解压单独的压缩流。
- libtool 的 `--enable-bsdtar=static` 只把 libarchive 静态链入，其他库仍是动态的；
  需要在 make 时用 `-all-static` 才是完全静态。

## 使用

```sh
./tar -czf etc.tar.gz /etc              # 需要目标机 gzip，见下文
./tar -xpf backup.tar -C /restore       # root 默认还原属主
./tar -cf - /data | ssh host 'cat > /backup/data.tar'
./tar -g snap.db -cf level0.tar /data   # 增量备份；还原用 -G -xf
./tar --xattrs --xattrs-include='*' --acls --selinux -cpf full.tar /srv

./bsdtar -czf etc.tar.gz /etc           # 内置压缩，不需要 gzip
./bsdtar --zstd -cf data.tar.zst /data
./bsdtar -xf anything.tar.xz            # 自动识别压缩和格式
./bsdtar -xf file.zip                   # 也可解 zip/7z/cpio/iso/rar
./bsdtar --format=zip --options=zip:encryption=aes256 --passphrase PASS -cf out.zip dir/
./bsdtar -tvf image.iso

./bsdunzip -o file.zip -d /opt/app     # 参数同 unzip，-x 写在 zip 文件名之后
./bsdunzip -P PASS aes.zip            # AES/ZipCrypto 加密
./bsdunzip -I GBK windows.zip         # Windows 中文版压缩的 zip；不能写 CP936
```

## 运行依赖与行为

### GNU tar 压缩需要外部程序和 /bin/sh

`-z/-j/-J/--zstd/--lzip/--lzop/-a` 以及解包时自动识别压缩格式，都是**调用外部压缩程序**：

- **创建**归档时，tar 通过 **`/bin/sh -c`** 启动压缩程序（源码 `src/system.c` 中写死）。
  目标机缺少 `/bin/sh` 时创建压缩包失败；缺少压缩程序时报 `gzip: not found`、`Child returned status 127`。
- **读取**归档时，tar 直接按 `PATH` 执行解压程序，缺少时报 `xz: Cannot exec: No such file or directory`。
- 目标机缺少对应程序时，改用 `bsdtar`；或者先用 `bsdtar` 解压/压缩，再交给 `tar`：
  `./bsdtar -xOf x.tar.zst > x.tar`，或 `./tar -cf - dir | ./bsdtar -cf out.tar.zst --zstd @-`。
- 不压缩的 tar 操作不依赖任何外部程序。`--to-command`、`--use-compress-program`、`--info-script`
  同样经过 `/bin/sh`。

### 其他

- **用户名/组名**：两者都只读 `/etc/passwd`、`/etc/group`，不走 NSS。LDAP/SSSD 用户在列表中显示为数字，
  解包时按归档里的数字 ID 还原（`--numeric-owner` 行为）。
- **trusted.\* xattr** 需要 CAP_SYS_ADMIN，`security.*` 受 LSM 策略限制，普通用户只能处理 `user.*`。
- **SELinux 标签**：GNU tar 的 `--selinux` 需要内核启用 SELinux 才能写回，未在 SELinux 系统上实测。
- **chattr 属性**：bsdtar 读写需要文件系统支持 `FS_IOC_GETFLAGS`（ext4/xfs 等），overlayfs 下可能不可用。
- **bsdunzip 中文文件名**：不按 locale 自动识别，需手动 `-I GBK`（或 `GB18030`）。
  musl iconv 没有 `CP936` 这个名字，`-I CP936` 报 `iconv_open failed: Cannot handle CP936`。
  `../` 和绝对路径的条目直接跳过（Info-ZIP unzip 是去掉前缀后解出）。
- **字符集**：bsdtar 的 `hdrcharset` 等转换用 musl 的 iconv，支持 UTF-8、GBK/GB18030、Big5、Shift_JIS 等常见编码，
  不如 glibc iconv 全面。GNU tar 不做文件名编码转换。

## 已知行为（不是静态编译造成的）

- **GNU tar 解 bsdtar 生成的归档时，目录 mtime 可能不对**：bsdtar 不保证同一目录的成员连续存放，
  GNU tar 默认离开目录就恢复其 mtime，之后解出该目录下的文件又改掉了。加 `--delay-directory-restore` 即可。
  用 Alpine 自带的 tar 1.35 + bsdtar 3.8.10 可复现，与本次构建无关。
- GNU tar 的 `-C` 是位置相关参数，需要放在 `-T` 或文件名之前。
- GNU tar 命令行用法错误时退出码为 64；操作失败为 2。
- bsdtar 与 GNU tar 大体兼容，但 `--transform`（bsdtar 用 `-s`）、增量备份 `-g`、
  `--exclude-vcs` 等 GNU 扩展不通用。

## 验证

构建阶段必须通过下列检查才导出：

1. **GNU tar 上游测试**：共 244 个用例，排除 1 个，222 个通过，21 个由测试套件自行跳过
   （需要非 root 的权限用例、需要 SELinux/capabilities 的用例、需要上游样例归档或 >2G 大文件的用例）。
   排除的是 `xattr03`（trusted.\*）：它只检查 uid 0，但 docker build 中的 root 没有 CAP_SYS_ADMIN；
   trusted.\* 已在宿主 root 下另行验证。
2. **libarchive 上游测试**：libarchive_test、bsdtar_test、bsdunzip_test 全部通过。
3. ELF 架构、`readelf -l` 无 `INTERP`、`readelf -d` 无 `NEEDED`；版本分别为 1.35、3.8.11；
   configure 确认 NLS、ACL、xattr、SELinux、远程 shell、rmt 路径及 bsdtar 各库宏均已启用。
4. `test/smoke-test.py`（165 项）：
   - GNU tar：gnu/posix 格式保留属主、setuid、目录权限、mtime、软/硬链接、FIFO、长路径、UTF-8 文件名和稀疏空洞；
     `-d` 比较；ustar 长名报错；6 种外部压缩的创建、`-a`、自动识别；缺少压缩程序时的报错；
     `host:file` 调用 `/usr/bin/ssh host /usr/sbin/rmt`；`-g`/`-G` 增量；`--exclude-vcs`、`--transform`、
     `--null -T`、`-r`、`--delete`、`--wildcards --strip-components`、`--to-command`；
     `--xattrs`、`--acls`、`--selinux`；中文翻译。
   - bsdtar（全部以 `PATH=/nonexistent` 运行）：完整树还原；9 种内置压缩读写及自动识别；
     zip/7z/cpio/iso9660/xar/ar/shar；zip AES-256 加解密和错误密码；mtree sha256；xattr、ACL、chattr 属性。
   - bsdunzip（同样无 PATH）：Info-ZIP zip 的内容/权限/链接/mtime，`-l -t -p -j -x -o`，ZipCrypto 和 AES 密码，
     bzip2/lzma 方法，`-I GBK`/`GB18030` 中文文件名，`-I CP936` 的报错，`../` 与绝对路径条目跳过。
   - 互相读取：两者生成的归档互解；xattr、ACL 互认；系统 gzip/xz/zstd 等能读 bsdtar 的压缩输出，
     系统 cpio 能读 bsdtar 的 newc。

测试主机和结果见 `test/VALIDATION.md`。

## Reference Documentation

- [GNU tar 主页](https://www.gnu.org/software/tar/)
- [GNU tar 下载目录](https://ftp.gnu.org/gnu/tar/)
- [GNU tar 手册](https://www.gnu.org/software/tar/manual/)
- [GNU tar 1.35 NEWS](https://git.savannah.gnu.org/cgit/tar.git/tree/NEWS?h=release_1_35)
- [libarchive 主页](https://www.libarchive.org/)
- [libarchive GitHub](https://github.com/libarchive/libarchive)
- [libarchive 3.8.11 发布页](https://github.com/libarchive/libarchive/releases/tag/v3.8.11)
- [bsdtar 手册页](https://github.com/libarchive/libarchive/wiki/ManPageBsdtar1)
- [libarchive 支持的格式](https://github.com/libarchive/libarchive/wiki/LibarchiveFormats)
