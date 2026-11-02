# 7-Zip 26.05 纯静态版

基于用户指定的官方 26.05 源码，使用 Alpine 3.22 + musl 构建 Linux
x86_64 / aarch64 的完整独立命令行版 `7zz`，不是格式裁剪版 `7za` / `7zr`。
静态链接 musl、libstdc++ 和 libgcc，运行不需要安装共享库、7z.so 或外部解压程序。

## 构建和产物

需要 Docker、默认 buildx，构建需要联网。默认只构建当前主机架构：

```sh
./build.sh
./build.sh amd64 --progress plain
./build.sh aarch64 --progress plain
./build.sh all             # 仅在已有跨架构执行能力时使用
```

优先分别在 x86_64 本机和 `192.168.182.150` aarch64 主机原生构建。
脚本不创建、修改或切换 builder，不安装模拟器。共享目录下不要并发构建同一架构。
编译默认 4 个任务，可用 `--build-arg JOBS=8` 调整。

```text
dist/
├── x86_64/                # 7zz、许可证、SHA256SUMS
├── aarch64/               # 7zz、许可证、SHA256SUMS
├── 7zip-26.05-linux-x86_64-static.tar.gz
└── 7zip-26.05-linux-aarch64-static.tar.gz
```

运行包不包含测试资料或源码。分发请保留 `License.txt`、`copying.txt`、
`unRarLicense.txt`，并按许可证要求提供对应源码及构建资料；RAR 代码有额外限制，
不能用于开发兼容 RAR 的压缩器。

固定源码文件 `7z2605-src.tar.xz`，校验 GitHub 官方发布资产中的 SHA-256：

```text
0b6080b8c3e7a579161d2d495224c0e51c467576cb4c7048b0ab485ef44cc22e
```

Alpine 镜像使用发行分支标签，编译器等依赖随该分支仓库更新，没有锁定全部传递依赖。
升级需要同时修改 Dockerfile 中的版本、源码文件编号及 SHA-256，以及测试版本断言和打包文件名。

## 离线使用

解开对应架构运行包，直接执行 `7zz`：

```sh
./7zz i                             # 版本、内置格式与编解码器
./7zz a -mmt=2 backup.7z ./data      # 压缩目录
./7zz x backup.7z -o./restored       # 保留目录结构解压
./7zz t backup.7z                   # 完整性检查
./7zz a -tzip backup.zip ./data
./7zz a -mhe=on -p secret.7z ./data  # 交互输入密码，包含文件名加密
./7zz x secret.7z -o./restored
```

建议显式设置线程数和合理压缩级别，避免大字典和过多线程导致内存不足。
不要在真实任务的命令行明文写密码，以免进入历史记录或进程列表。

## 功能与取舍

- 保留上游 Alone2 的全部格式和编解码器，包括 RAR/RAR5 解压、7z AES、ZIP AES。
  具体格式的读写能力看 `7zz i`；能解压不代表能创建，例如 RAR 只能读，不能创建。
- x86_64 使用官方 `cmpl_gcc.mak` 的 C/C++ 实现，没有引入额外 MASM 汇编器；
  保留源码中的 CPU 检测及 C intrinsic 优化，部分性能可能低于官方手写汇编构建，未做性能对比。
- aarch64 使用官方 `cmpl_gcc_arm64.mak`，包含上游 ARM64 汇编优化。
  不使用 `-march=native`，不针对构建机 CPU 定制。
- 不包含 Windows GUI、资源管理器集成、独立 SFX 模块或外部动态编解码插件。
  内置格式不需要插件；静态 musl 不适合动态加载第三方 `.so` 扩展。
- 仍需要 Linux 内核、线程支持、内存和文件权限；正常系统应提供 `/dev/null`、
  `/dev/urandom`（上游加密随机种子读取该设备），CPU/内存探测可能读取 `/proc`。
  加密测试通过不代表应移除目标系统的随机数设备。
- 不适合替代 Linux 完整系统备份工具：不要假定可完整保留所有权、ACL、扩展属性等元数据。
  对不可信压缩包应使用低权限账户和独立目录解压。

## 验证

构建阶段必须通过下列检查才导出：

1. `file` 和 `readelf -h` 检查目标架构；`readelf -l/-d` 检查没有 `INTERP` 和 `NEEDED`。
2. 版本确认为 26.05，内置格式包含 RAR/RAR5。
3. `test/smoke-test.py` 在仅包含二进制及数据的临时 chroot 中执行，
   没有共享库、动态加载器、shell、插件和辅助程序；`/dev/null` 使用普通文件替代，
   `/dev/urandom` 使用宿主 Python 生成的 64 KiB 随机种子测试文件，不能用于生产部署。
4. 7z / ZIP / tar 目录压缩解压，逐字节比较中文及空格文件名、空文件、随机内容。
5. 与 Python 标准库双向验证 gzip / bzip2 / xz，并使用 Python 独立解压 ZIP。
6. 7z 文件头加密、ZIP AES256 加密、正确密码解压和错误密码失败。
7. 标准输入输出、SHA-256，以及截断压缩包必须返回失败。

测试只覆盖常用功能，并非上游完整测试套件；RAR/RAR5 仅检查编入，
未用真实 RAR 样本验证，也未遍历测试所有内置格式或所有旧内核/CPU。
实际构建主机及结果见 `test/VALIDATION.md`。

## Reference Documentation

- [用户指定的官方 26.05 发布页](https://github.com/ip7z/7zip/releases/tag/26.05)
- [官方源码包](https://github.com/ip7z/7zip/releases/download/26.05/7z2605-src.tar.xz)
- [官方发布资产及哈希 API](https://api.github.com/repos/ip7z/7zip/releases/tags/26.05)
- [固定版本源码说明及 Linux 编译方法](https://github.com/ip7z/7zip/blob/26.05/DOC/readme.txt)
- [完整独立版本 Alone2 makefile](https://github.com/ip7z/7zip/blob/26.05/CPP/7zip/Bundles/Alone2/makefile.gcc)
- [官方许可证](https://github.com/ip7z/7zip/blob/26.05/DOC/License.txt)

本项目已阅读校验后的官方源码包中对应文档和 Makefile，不对上游源码打补丁。
