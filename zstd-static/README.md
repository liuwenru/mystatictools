# pzstd 1.5.7 纯静态构建

使用 Alpine 3.22 + musl，从 zstd 1.5.7 官方源码中的 `contrib/pzstd` 构建
Linux x86_64 和 aarch64 二进制。静态链接 libzstd、libstdc++、libgcc 和 musl，
目标机器无需安装这些共享库，也不需要 Alpine 系统。

## 构建

需要 Docker 和默认 buildx。跨架构需要宿主机**已有**可用的 binfmt/QEMU；
脚本不会安装模拟器，也不创建、修改或切换 builder。构建需要联网，运行可以离线。

```sh
./build.sh                 # 两种架构
./build.sh amd64           # 也接受 x86_64、linux/amd64
./build.sh aarch64         # 也接受 arm64、linux/arm64
./build.sh all --progress plain
```

产物目录：

```text
dist/
├── x86_64/
│   ├── pzstd
│   ├── LICENSE.zstd
│   └── SHA256SUMS
└── aarch64/
    ├── pzstd
    ├── LICENSE.zstd
    └── SHA256SUMS
```

源码固定版本并校验官方发布的 SHA-256：
`eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3`。
升级时必须同时更新 Dockerfile 中的 `ZSTD_VERSION` 与 `ZSTD_SHA256`，
或同时通过 `--build-arg` 传入。Alpine 镜像使用发行分支标签，软件包随该分支仓库更新，
没有锁定全部传递依赖。本构建未使用 `-march=native`，不针对构建机 CPU 定制指令集。

## 离线使用

复制对应架构的 `pzstd` 即可使用；分发时请保留随附的许可证。

```sh
chmod +x ./pzstd
./pzstd --version
./pzstd -p 4 -3 input-file -o input-file.zst
./pzstd -p 4 -d input-file.zst -o restored-file
./pzstd -p 4 -t input-file.zst

# 从标准输入压缩/解压
cat input-file | ./pzstd -p 4 -c > input-file.zst
./pzstd -p 4 -d -c input-file.zst > restored-file
```

原文件默认保留。已有输出需要显式使用 `-f` 才覆盖。
建议显式设置 `-p`，避免默认使用系统探测到的全部 CPU 而占用过多内存和线程。

### 功能与限制

- 保留上游 pzstd 功能，不通过裁剪功能实现静态链接。
- 将输入分块为独立 zstd 帧并加入可跳过的长度元数据，可并行压缩和解压自己生成的文件。
- 输出符合 zstd 格式，标准 zstd 可以解压；pzstd 也可解压不依赖字典的普通 zstd 文件。
  对普通 zstd 文件，pzstd 通常一个线程做 I/O、另一个线程解码，**不是任意 zstd 文件都能并行解码**。
- 支持 `-p`、压缩级别 1–19、`--ultra`、校验、文件与标准输入输出。
- 上游不支持字典模式、稀疏文件模式及 zstd benchmark 选项；不是完整 zstd CLI 的替代品，
  以 `./pzstd --help` 为准。
- 本产物只有 pzstd，不包含标准 zstd CLI、tar、shell 或其他辅助程序。
- 无需额外数据文件、证书、插件或解释器。仍需要 Linux 内核、线程支持、足够内存、
  输入读取和输出写入权限；`-t` 使用 `/dev/null`，默认线程数探测需要内核 CPU 信息。
  管道示例中的 shell 和 `cat` 由目标系统提供，并非 pzstd 自身运行依赖。

## 验证

每种架构必须通过以下检查后才导出：

1. `file`、`readelf -h` 检查目标架构；`readelf -l/-d` 检查无 `INTERP` 和 `NEEDED`。
2. 检查版本为 `PZSTD version: 1.5.7.`。
3. `smoke-test.py` 在只放入二进制、测试数据和一个 `/dev/null` 替代普通文件的 chroot 中
   运行 pzstd；其中没有共享库、动态加载器、shell 或辅助程序。
4. 约 13 MiB 多帧数据使用两个工作线程压缩/解压，逐字节比较恢复结果；执行完整性检查。
5. 与同一官方源码构建的标准 zstd 双向互通。
6. 标准输入输出往返、空输入，以及损坏/截断输入必须返回失败。

标准 zstd 仅作为构建阶段的互通测试工具，不随产物导出。
这些是功能冒烟测试，并未执行依赖 GoogleTest 的上游完整测试套件或性能基准。
本机为 x86_64：amd64 原生执行，arm64 通过已有模拟器执行；
模拟器测试不能替代真实 aarch64 目标机和实际业务数据验证。

## Reference Documentation

- [用户提供的 pzstd README（dev）](https://github.com/facebook/zstd/blob/dev/contrib/pzstd/README.md)
- [固定版本 pzstd README](https://github.com/facebook/zstd/blob/v1.5.7/contrib/pzstd/README.md)
- [pzstd Makefile](https://github.com/facebook/zstd/blob/v1.5.7/contrib/pzstd/Makefile)
- [pzstd 命令选项及功能限制](https://github.com/facebook/zstd/blob/v1.5.7/contrib/pzstd/Options.cpp)
- [zstd 1.5.7 官方发布页](https://github.com/facebook/zstd/releases/tag/v1.5.7)
- [官方源码 SHA-256](https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz.sha256)
