# dos2unix 7.5.7 纯静态构建

使用 Alpine 3.22 + musl 从上游源码构建 Linux **x86_64** 和 **aarch64** 版本。
无需 Alpine 系统、动态加载器或共享库，复制对应架构的二进制即可离线使用。

## 产物

```text
dist/
├── x86_64/
└── aarch64/
    ├── dos2unix
    ├── unix2dos
    ├── mac2unix -> dos2unix
    ├── unix2mac -> unix2dos
    ├── LICENSE.dos2unix
    ├── SHA256SUMS
    ├── 使用手册.txt
    └── usr/share/locale/     # 可选的界面翻译
```

两种架构的目录结构相同。仅使用 dos2unix 时只需复制 `dos2unix`；分发请保留许可证。
mac2unix/unix2mac 是上游支持的按程序名选择模式的符号链接，需与对应实体程序一起复制。

## 使用

```sh
chmod +x ./dos2unix
./dos2unix --version
./dos2unix file.txt                    # 原地将 CRLF 转成 LF
./dos2unix -n input.txt output.txt     # 保留原文件，另存输出
./dos2unix -k file.txt                 # 保留修改时间
./dos2unix -e file.txt                 # 末尾没有换行时补上
./dos2unix < input.txt > output.txt    # 标准输入输出
./unix2dos file.txt                    # LF 转成 CRLF
./mac2unix file.txt                    # 旧 Mac 的 CR 转成 LF
```

注意：默认原地修改文件，重要文件请先备份；标准输入输出不要重定向到同一输入文件。
递归处理需使用目标系统自己的 `find` 等命令，本工具不内置目录递归。

### 功能和运行依赖

- 保留上游 NLS、Unicode UTF-16 和大文件支持，没有为静态链接裁剪转换功能。
- 支持 UTF-8、带 BOM 的 UTF-16LE/BE、BOM 处理、7-bit/ISO 模式及文件信息查询。
- UTF-16 转为 UTF-8 时建议设置 `LANG=C.UTF-8`；musl 内置 UTF-8 支持，不需要外部 locale 数据。
- 默认跳过二进制文件、非普通文件和符号链接；可通过上游选项改变行为。
- 英文提示无需额外文件。界面翻译使用可选的 `.mo` 文件，按目录层次复制
  `usr/share/locale/` 到目标机 `/usr/share/locale/`，再设置相应 UTF-8 locale。
  不安装翻译文件不影响中文文本内容的转换。
- 运行不需要解释器、证书、网络、插件或辅助程序。仍需 Linux 内核、输入读取权限和
  输出目录写入权限；原地转换需在原文件目录创建临时文件，所有权保留受用户权限限制。
- 不保证 musl 支持所有 glibc 的传统 locale/编码行为；真实目标系统及业务文件仍需验证。

## 构建

需要 Docker 和默认 buildx；构建需要联网。建议分别在对应架构主机原生构建：

```sh
sh ./build.sh x86_64 --progress plain
sh ./build.sh aarch64 --progress plain
# 已有跨架构支持时也可在一台主机执行；脚本不会安装模拟器：
sh ./build.sh all
```

支持 `amd64`、`arm64`、`linux/amd64`、`linux/arm64` 别名。脚本只使用
`--builder default`，不创建、修改或切换 builder。不要在两台共享仓库的主机上
同时导出同一架构产物。

源码固定为官方稳定版 7.5.7（2026-08-27），下载后校验 SHA-256：

```text
669ee27120ae71589f638fe3a167d6ea54f8633f5ab1b282551bd7a7c9510dfa
```

该值由本次下载的官方发布压缩包计算，不声称来自独立签名验证。
升级时需同步更新 Dockerfile 的 `DOS2UNIX_VERSION` 和 `DOS2UNIX_SHA256`。
Alpine 使用 3.22 分支标签，构建依赖随该分支仓库更新，未锁定镜像摘要及全部软件包版本。
没有使用 `-march=native`。转换程序与 musl、gettext 的 libintl 静态链接；
构建时通过 gettext 生成翻译文件，musl-locales 仅用于测试时枚举 locale。

许可证：dos2unix 为 BSD-2-Clause，musl 为 MIT，静态链接的 GNU libintl 为
LGPL-2.1-or-later。若对外分发二进制，除保留 dos2unix 许可证外，还需随附依赖的
许可文本，并按 LGPL 要求提供对应源码及重新链接所需材料；当前目录不是完整的对外合规分发包。

## 验证

构建导出前执行：

1. 上游 `make -C test test UCS=1` 测试套件（保留其 locale 条件跳过机制）。
2. `file`、`readelf -h` 检查 ELF 架构，`readelf -l/-d` 检查无 `INTERP` 和 `NEEDED`。
3. 检查两个实体程序的版本号。
4. `smoke-test.py` 在不含共享库、shell、翻译文件和外部 locale 数据的独立 chroot 中，
   验证 CRLF/LF/CR 转换、标准输入输出、中文 UTF-16LE/BE、UTF-8 BOM、空输入、
   补末尾换行、原地修改、另存输出、时间戳保留、二进制和符号链接保护。

本次验证（2026-10-22）：

| 架构 | 构建/测试主机 | 结果 | dos2unix 大小 |
| --- | --- | --- | --- |
| x86_64 | 本机，原生 | 上游 9 个测试文件 / 174 项测试、隔离测试及导出后复测通过 | 约 262 KiB |
| aarch64 | 192.168.182.150，原生 | 上游 9 个测试文件 / 174 项测试、隔离测试及导出后复测通过 | 约 330 KiB |

两者均使用各自主机的默认 Docker builder，ELF 架构、静态链接及 SHA256SUMS 检查通过。
未执行要求 `zh_CN.gb18030` locale 的上游专项测试；不能据此声称支持该 locale。
这些测试不替代真实离线业务环境验收。

## Reference Documentation

- [官方发布页（版本与下载链接）](https://dos2unix.sourceforge.io/)
- [上游新主页](https://waterlander.net/dos2unix/)
- [官方构建说明](https://dos2unix.sourceforge.io/dos2unix/INSTALL.txt)
- [官方中文手册](https://dos2unix.sourceforge.io/dos2unix/zh_CN/man1/dos2unix.htm)
- [7.5.7 官方源码](https://downloads.sourceforge.net/project/dos2unix/dos2unix/7.5.7/dos2unix-7.5.7.tar.gz)
- [上游源码仓库](https://sourceforge.net/p/dos2unix/dos2unix/)

实际构建参数以固定版本源码中的 `Makefile`、`INSTALL.txt` 和 `test/Makefile` 为依据。
