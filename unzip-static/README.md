# UnZip 6.0（Ubuntu 6.0-31ubuntu1 补丁）纯静态版

Info-ZIP UnZip 6.0，即各发行版自带的 `unzip`，参数和输出格式与系统 unzip 一致。
Alpine 3.22 + musl 从源码静态构建，支持 Linux x86_64 / aarch64，运行时不需要共享库或动态加载器。

- 上游 6.0 于 2009-04-20 发布，此后没有新正式版；各发行版靠补丁维护安全修复。
- 补丁采用 **Ubuntu 6.0-31ubuntu1**：Debian 6.0-31（2026-08-10，sid/forky 当前版本，含历年 CVE 修复）
  的全部 34 个补丁，再加 Ubuntu 的 4 个补丁：`-O`/`-I` 文件名字符集、代码页修正、CVE-2021-4217、手册页修正。
  Debian 本身没有 `-O`/`-I`，中文 Windows 压缩的 zip 需要它，所以选 Ubuntu 补丁集。

同一仓库的 `tar-static` 还附带 libarchive 的 `bsdunzip`，两者区别见下文“与 bsdunzip 的区别”。

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
├── x86_64/       # unzip、zipinfo -> unzip、funzip、unzip.1、zipinfo.1、funzip.1、LICENSE.unzip、SHA256SUMS
├── aarch64/
├── unzip-6.0-31ubuntu1-linux-x86_64-static.tar.gz
└── unzip-6.0-31ubuntu1-linux-aarch64-static.tar.gz
```

| 文件 | x86_64 | aarch64 | 说明 |
| --- | --- | --- | --- |
| `unzip` | 约 425 KB | 约 457 KB | 解压、列表、测试 |
| `zipinfo` | | | 指向 unzip 的符号链接，等同 `unzip -Z`；单独复制时用 `unzip -Z` |
| `funzip` | 约 53 KB | 约 65 KB | 从管道解出第一个成员 |
| `*.1`、`LICENSE.unzip` | | | 手册页（含 `-O`/`-I` 说明）、Info-ZIP 许可证 |

未打包 `unzipsfx`（自解压文件的头部，运维场景用不到）和 `zipgrep`（依赖系统 egrep/sed 的 shell 脚本），
两者都会构建并通过测试，需要时可加入 `build.sh` 的文件列表。

### 固定版本与校验

| 组件 | 来源 | SHA-256 | 校验依据 |
| --- | --- | --- | --- |
| unzip60.tar.gz | SourceForge（Info-ZIP 官方） | `036d9699…bd37` | 与 Debian/Ubuntu `unzip_6.0.orig.tar.gz` 逐字节相同，与两者 .dsc 中的哈希一致 |
| unzip_6.0-31ubuntu1.debian.tar.xz | archive.ubuntu.com | `7a39f161…b221c` | 与 Ubuntu .dsc 中的哈希一致 |

完整哈希见 Dockerfile。Alpine 依赖随 3.22 分支仓库更新，未锁定版本，本次实际使用：
gcc 14.2.0、musl 1.2.5、bzip2-static 1.0.8。
升级补丁集时同步修改 Dockerfile 中的版本和哈希、`build.sh` 中的版本，并确认 `patches/` 中的本地补丁仍能打上。

## 编译取舍

- **编译宏与 Debian `debian/rules` 相同**：Unicode/UTF-8 文件名、Zip64 和 >2 GiB 文件、bzip2、
  Deflate64、符号链接、`-X` 还原 uid/gid、`YYYY-MM-DD` 日期格式。bzip2 用 Alpine 的静态 libbz2。
- **本地补丁 `patches/musl-iconv-cp936.patch`**：musl 的 iconv 支持 GBK/GB18030，但不认 `CP936` 这个名字，
  而补丁按 locale 自动选择的中文代码页、Windows 和各种教程里用的写法都是 CP936，不处理时中文文件名全部乱码。
  补丁只在 iconv 打不开 `CP936` 时改用 GB18030（CP936 的超集），解码结果相同。
- 二进制已 strip。上游 `make check` 和 Ubuntu autopkgtest 均在构建时运行。

## 使用

```sh
./unzip file.zip                      # 解压到当前目录
./unzip -o file.zip -d /opt/app       # 覆盖已有文件，解到指定目录
./unzip -l file.zip                   # 列表；-v 显示压缩方法、CRC
./unzip -t file.zip                   # 测试完整性
./unzip -p file.zip conf/app.yml      # 输出到 stdout
./unzip file.zip -x '*.bak'           # -x 写在 zip 文件名之后
./unzip -O CP936 windows.zip          # Windows 中文版压缩的 zip，也可写 GBK
./unzip -Z -1 file.zip                # zipinfo：只列文件名
curl -s http://host/x.zip | ./funzip > x   # 管道解第一个成员（仅 deflate/stored）
```

## 中文文件名

zip 里文件名的编码有两种：

1. 设置了 UTF-8 标志（7-Zip、新版 Windows、Linux zip、Python 等）：直接按 UTF-8 解出，不需要任何选项。
2. 未设置标志，按压缩时系统的本地编码存放（Windows 中文版资源管理器、旧版 WinRAR 等常见，多为 GBK）：
   - `LANG`/`LC_ALL` 为 `zh_CN.*` 或 `zh_SG.*` 时，自动按 CP936 转换；
   - 没有设置 locale 时**不猜测**，原样写出字节，文件名显示为乱码，此时加 `-O CP936`（或 `-O GBK`）；
   - `zh_TW`/`zh_HK` 自动按 CP950（Big5），`ja_JP` 按 CP932，`ko_KR` 按 CP949。
   - `-I` 指定 Unix 端（ISO）编码，用法同 `-O`。

musl iconv 缺少 CP720/737/775/852/855/857/862/874 等 DOS 代码页（阿拉伯、希腊、波罗的海、中欧、
土耳其、希伯来、泰文）。这些语言 locale 下的非 UTF-8 zip 不做转换，文件名为原始字节；中、日、韩、
俄文（CP866）及 Windows CP125x 均可用。

## 运行依赖与行为

- 不依赖任何外部程序、locale 文件或 iconv 模块：字符集转换由 musl 内置实现完成。
- **用户名/组名**：`-X` 按 zip 中记录的数字 uid/gid 还原，需要 root；不查 NSS。
- **时区**：时间显示和 DOS 时间换算读 `TZ` 和 `/etc/localtime`；没有这两者时按 UTC。
  Info-ZIP、7-Zip 等写入的 UT 扩展字段是 UTC 时间戳，不受时区影响。
- **不支持的压缩方法和加密**：AES 加密（WinZip AES，method 99）、zstd、xz、lzma、ppmd 等报
  `unsupported compression method`。改用 `bsdunzip`（tar-static）或 `7zz`（7zip-static）。
  支持：store、shrink、implode、deflate、deflate64、bzip2 和传统 ZipCrypto 密码。
- **funzip** 只处理 deflate/stored 的第一个成员，遇到 bzip2 报 `first entry not deflated or stored`。
- **路径安全**：`../` 和绝对路径会被去掉前缀后解到目标目录内；重叠成员的 zip 炸弹（CVE-2019-13232）会被拒绝，退出码 12。

## 与 bsdunzip 的区别

| | unzip（本包） | bsdunzip（tar-static） |
| --- | --- | --- |
| 参数/输出 | 与发行版 unzip 完全一致，有 zipinfo、funzip | 常用参数兼容，`-l` 输出格式略有不同，无 zipinfo |
| 中文 GBK 文件名 | 按 locale 自动识别；`-O CP936`/`-O GBK` | 只能手动 `-I GBK`，`CP936` 在 musl 下不可用 |
| AES 加密、zstd/xz/lzma | 不支持 | 支持 |
| `../` 条目 | 去掉 `../` 后解到目标目录内 | 跳过该条目 |

## 验证

构建阶段必须通过下列检查才导出：

1. 上游 `make check`：解压、zipinfo、`-d`、`-o`、funzip、unzipsfx。
2. ELF 架构、`readelf -l` 无 `INTERP`、`readelf -d` 无 `NEEDED`；`unzip -v` 显示 Debian 版本及
   `USE_BZIP2`、`ZIP64_SUPPORT`、`UNICODE_SUPPORT`。
3. Ubuntu autopkgtest（`debian/tests/SmokeTests.py`）：运行 34 项全部通过，涵盖 unzip/zipinfo/funzip/unzipsfx 的
   单文件、多文件、500 MiB 大文件、密码、损坏文件和 Unicode 文件名。排除 11 项：5 项手册页
   （依赖 man-db 的 `man -P cat`，构建容器不可用，改由 smoke 测试用 mandoc 检查）和 6 项 zipgrep（不进运行包）。
4. `test/smoke-test.py`（37 项，无 PATH 运行）：GBK 文件名在无 locale/`LANG`/`LC_ALL` 下的表现，
   `-O CP936`/`cp936`/`GBK`/`GB18030`，`-l`、zipinfo 中文显示，Big5、Shift_JIS 自动识别，UTF-8 标志不重复转换；
   bzip2、Zip64 头（force_zip64）、`-t`、ZipCrypto 正确/错误密码；权限、符号链接、mtime、`-X` uid/gid；`-l` 格式、zipinfo 链接调用、
   `-Z -1`、`-p`、`-j -x`、未匹配退出码；funzip；zip 炸弹、`../` 与绝对路径；手册页渲染及 `-O`/`-I` 说明。

测试主机和结果见 `test/VALIDATION.md`。

## Reference Documentation

- [Info-ZIP UnZip 主页](https://infozip.sourceforge.net/UnZip.html)
- [Info-ZIP SourceForge 下载](https://sourceforge.net/projects/infozip/files/UnZip%206.x%20%28latest%29/UnZip%206.0/)
- [Debian unzip 源码包](https://tracker.debian.org/pkg/unzip)
- [Ubuntu unzip 源码包](https://launchpad.net/ubuntu/+source/unzip)
- [unzip(1) 手册页](https://manpages.ubuntu.com/manpages/en/man1/unzip.1.html)
- [musl 与 glibc 的差异](https://wiki.musl-libc.org/functional-differences-from-glibc.html)
