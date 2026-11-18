# lrzsz 0.13.1 纯静态版

Alpine 3.22 + musl，提供 Linux x86_64 / aarch64 产物。核心程序为 `lrz`、`lsz`，
附带 `rz/sz`（ZMODEM）、`rb/sb`（YMODEM）、`rx/sx`（XMODEM）及带 `l` 前缀的入口。
这些入口是符号链接，程序按调用名称选择协议，复制时需保留相应名称。

## 使用

解压对应架构的压缩包，将程序放入 PATH，或直接使用相对路径：

```sh
./rz -b                  # 从终端客户端上传，保存到当前目录
./sz -b example.tar.gz   # 下载到终端客户端
./rz -b -r               # 尝试续传
./sz -b -r example.tar.gz
./rx -b example.bin      # XMODEM 接收文件，使用相对路径
./sx -b example.bin
```

终端客户端必须支持对应协议，连接链路需能透明传递协议字节。静态程序不会给 SSH 客户端增加 ZMODEM 支持。
目标机需要 Linux 内核、文件读写权限，以及终端/串口或其他双向字节通道。
常规文件传输不需要共享库、shell、证书、配置、翻译文件或 terminfo。
syslog 保留上游默认行为；日志写入需要系统日志 socket，独立运行可加 `--syslog=off`。

## 功能与版本取舍

- 保留 X/Y/ZMODEM、二进制传输、批量传输、续传、目录创建及 syslog。
- 使用 `--disable-nls`：提示信息为英文，省去 gettext 库和外置翻译文件，不影响文件内容。
- 0.13.1 是官方 2026 年 10 月发布版。0.13 系列包含安全修复，移除了远程命令执行、旧 TCP 扩展等功能。
- 新版发送端不再发送旧的 `rz\r` 自动下载触发串，客户端应识别 ZRQINIT；旧客户端需实际验证。
- 新版限制接收路径，拒绝绝对路径和不安全的路径/符号链接。接收时先进入目标目录。
- XMODEM 不携带原始文件长度，接收文件可能带块填充；需要准确长度和批量传输时优先 ZMODEM。

## 构建

在仓库根目录执行（需 Docker、默认 buildx，安装 Alpine 构建依赖需要联网）：

```sh
./lrzsz-static/build.sh amd64 --progress plain
# 在 192.168.182.150 的 /root/workspace/mystatictools 原生构建 ARM：
./lrzsz-static/build.sh aarch64 --progress plain
```

脚本只使用默认 builder，不创建或切换 builder，也不安装模拟器。默认仅构建当前主机架构。
使用官方发行包内的 configure，`CFLAGS=-O2 LDFLAGS=-static`，不修改上游源码。

产物位于：

```text
dist/x86_64/                                  # 二进制、入口链接、手册、COPYING、SHA256SUMS
dist/aarch64/
dist/lrzsz-0.13.1-linux-x86_64-static.tar.gz
dist/lrzsz-0.13.1-linux-aarch64-static.tar.gz
```

核心二进制每个约 130–200 KiB（因架构而异）。压缩包保留入口链接。
构建校验哈希后才编译，静态属性及传输测试通过后才导出。
发布脚本 `pushfdoc.sh` 仅在明确要求发布时手工执行。

## 源码与依赖

官方原始源码包保存在 `sources/lrzsz-0.13.1.tar.gz`，作为重建材料及 GPL 源码一并保留。
分发二进制时请同时提供对应源码与本目录的构建文件、测试文件和说明。

- 来源：<https://ohse.de/uwe/releases/lrzsz-0.13.1.tar.gz>
- SHA-256：`112f91059fbd118e016d800c1a5c5a1702e965d8b9bfbda6015e44e20bfb93c9`
- 哈希根据本次从官方 HTTPS 下载的文件计算并固定，未核验独立签名。
- lrzsz 固定为 0.13.1；musl、GCC、binutils 等随 Alpine 3.22 仓库更新，未逐包锁定。
- Python 仅用于构建时测试，不进入交付包，运行工具不需要 Python。

## 验证

本次 x86_64 在 192.168.188.150 原生构建，aarch64 在 192.168.182.150 原生构建。
构建阶段执行：

1. `readelf -h` 检查 ELF 架构；`readelf -l` 无 INTERP；`readelf -d` 无 NEEDED。
2. 所有 12 个程序入口的 `--version` 均显示 0.13.1。
3. `test/transfer.py` 用 socketpair 连接发送与接收进程，在无共享库、shell、数据文件的 chroot 内测试：
   - ZMODEM / YMODEM：空文件、UTF-8 文本和包含全部字节值的 2 MiB 二进制，接收后逐字节比较。
   - XMODEM：4096 字节整块二进制，接收后逐字节比较。
   - ZMODEM：已有 64 KiB 前缀时请求续传，最终文件逐字节一致。

这是两端同版本的协议测试，未验证真实串口、实际 SSH 终端客户端、跨实现互通、真实断线重连或老内核。
未运行上游完整 `make vcheck` 测试套件。

## Reference Documentation

- [官方主页与发布记录](https://ohse.de/uwe/software/lrzsz.html)
- [0.12 / 0.13 兼容性变化](https://ohse.de/uwe/software/lrzsz/compatibility-0.13.txt)
- [官方源码仓库](https://github.com/UweOhse/lrzsz)
- `sources/` 发行包中的 `man/lrz.1`、`man/lsz.1`、`README.tests`、`COPYING`
