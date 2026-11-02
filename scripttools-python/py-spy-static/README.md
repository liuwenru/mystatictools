# py-spy 0.4.2 纯静态构建

[py-spy](https://github.com/benfred/py-spy) 是 Python 采样分析器：不改代码、不重启进程，
直接读取目标进程内存得到 Python 调用栈。py-spy 用 Rust 编写，本目录用 Alpine 3.24 +
musl 编出 x86_64 和 aarch64 两个架构的 static-pie 二进制，**不是** PyInstaller 打包。
保留上游 Linux 发布版的全部功能，包括依赖 libunwind 的 `--native`。

## 构建

需要 Docker 和默认 buildx；脚本只使用 `--builder default`，不安装模拟器、不改宿主机。
构建时需要联网（下载 Alpine 包、py-spy 源码和 crates），运行可完全离线。

```sh
./build.sh amd64      # 也接受 x86_64、linux/amd64
./build.sh aarch64    # 也接受 arm64、linux/arm64，建议在 ARM 主机原生构建
./build.sh            # 两种架构；非本机架构需要宿主机已有 binfmt/QEMU
```

产物：

```text
dist/x86_64/{py-spy,LICENSE.py-spy,SHA256SUMS}
dist/aarch64/{py-spy,LICENSE.py-spy,SHA256SUMS}
```

### 版本与依赖固定方式

| 内容 | 固定方式 |
| --- | --- |
| py-spy 源码 | `v0.4.2` tag 源码包，SHA-256 `ecf8d945f63b172126abcd68e21f3e5f250498cb774d88247d80a6f2cacdb998` |
| Rust crates | 上游 `Cargo.lock` + `cargo build --locked`，crates.io 校验和 |
| rust/cargo、libunwind、xz、zlib、musl | 随 Alpine 3.24 分支仓库更新，未锁定小版本（构建时为 rust 1.96.1、libunwind 1.8.3、xz 5.8.4） |

升级 py-spy 时同时修改 Dockerfile 中的 `PY_SPY_VERSION` 和 `PY_SPY_SHA256`。

### 为什么这样链接

上游 musl 版本在自家交叉编译镜像中构建，依赖 `remoteprocess` 的 build.rs 从
`/usr/local/musl/<target>/lib` 复制 libunwind.a，Alpine 上没有这个路径。使用 Alpine 自带
rust（target 为 `*-alpine-linux-musl`）时，build.rs 改为输出
`dylib=lzma,unwind,unwind-ptrace,unwind-<arch>`，直接加 `crt-static` 会出现两个问题：

1. rustc 用 `-Bdynamic` 链接这几个库，ld 优先选 `.so`，产物里留下 `NEEDED libunwind-ptrace.so.0`
   但没有动态解释器，无法运行。处理：只在构建容器里删掉 `libunwind*.so`、`liblzma.so`
   这些链接用符号链接，ld 自动退回 `.a`。
2. 静态库顺序不对（lzma 在 libunwind 之前，`_U<arch>_setcontext` 在 libunwind.a 中），
   出现 undefined reference。处理：在链接命令末尾追加 `-Wl,-Bstatic -lunwind -llzma`；
   `-Bstatic` 不能省，否则 gcc 末尾隐式的 `-lc` 会选到 musl 的 libc.so。

另外必须显式传 `--target`，否则 `crt-static` 也作用到 proc-macro（clap_derive），编译失败。

Dockerfile 在构建阶段检查：ELF 架构、无 `INTERP`、无 `NEEDED`、`--version` 为 `py-spy 0.4.2`。

## 使用

复制对应架构的 `py-spy` 即可，不依赖目标机的 Python、glibc、musl 或 libunwind。

```sh
./py-spy top --pid 12345                      # 类 top 实时视图，需要终端
./py-spy dump --pid 12345                     # 打印当前所有线程调用栈
./py-spy dump --pid 12345 --native            # 同时显示 C/C++/Cython 扩展帧
./py-spy record -o profile.svg --pid 12345    # 火焰图，Ctrl-C 结束
./py-spy record -d 30 -f speedscope -o p.json --pid 12345
./py-spy record -o profile.svg -- python3 app.py   # 由 py-spy 启动被测程序
./py-spy completions bash > /etc/bash_completion.d/py-spy
```

`record` 输出格式：`flamegraph`（SVG，默认）、`speedscope`、`raw`、`chrometrace`。
SVG 自带脚本，离线浏览器可直接打开；speedscope JSON 需在 speedscope 中查看
（离线时需自行部署 speedscope 静态页面）。

## 运行条件与限制

- **权限**：py-spy 通过 `process_vm_readv` 读取目标进程，`--native` 和非 `--nonblocking`
  模式还要 ptrace 暂停线程。一般用 root 运行；非 root 只能分析自己启动的子进程，
  且受 `/proc/sys/kernel/yama/ptrace_scope` 限制。
- **容器**：分析容器内进程需要 `SYS_PTRACE` 能力（`docker run --cap-add SYS_PTRACE`），
  或在宿主机上用 root 按宿主机 PID 分析。Kubernetes 需要在 securityContext 中加
  `SYS_PTRACE`。
- **`--native`**：本构建的 x86_64、aarch64 都已启用（上游在 Linux 上只对 x86_64/arm/aarch64 启用）。
  目标进程的 `.so` 被 strip 后 C 帧只显示地址，不影响 Python 帧。
- **`top`** 需要可用终端（读取 `TERM`/terminfo 失败时显示会变差，但 `dump`、`record` 不受影响）。
- **Python 版本**：由 py-spy 0.4.2 内置的结构体定义决定（`src/python_bindings/`），覆盖 CPython 2.7、
  3.3–3.14；不支持 PyPy。目标 Python 若完全去掉符号表，py-spy 会退回扫描内存查找解释器状态，可能变慢或失败。
- 不使用 `-march=native`，不针对构建机 CPU 定制指令集。

## 测试

```sh
test/smoke-test.sh x86_64      # 默认使用 python:3.12-slim 镜像
test/smoke-test.sh aarch64 [镜像]
```

脚本先在宿主机用 readelf 检查架构、INTERP、NEEDED 和 SHA256SUMS，再在
`--network none`、只加 `SYS_PTRACE` 的 Debian glibc 容器（无 musl、无 libunwind）中运行：
`record`（svg/speedscope/raw、`--subprocesses`、`--idle`、`--gil`）、对非子进程 `dump --pid`、
`dump --native`（要求出现 `.so` 中的 C 帧）、`record --native`（要求出现 libz 的 `deflate` 帧）、`completions`。
测试资料只在 `test/`，不进入 `dist/`。

## 验证记录

| 架构 | 构建主机 | 测试方式 | 结果 |
| --- | --- | --- | --- |
| x86_64 | 本机 x86_64，原生构建 | 原生，python:3.12-slim（glibc 2.41，Python 3.12.16），断网容器 | 全部通过 |
| aarch64 | 192.168.182.150（aarch64），原生构建 | 原生，同上 | 全部通过 |

两个架构都没用模拟器。产物 SHA-256：x86_64 `6613e463…`，aarch64 `2921ece6…`（完整值见各自的 `SHA256SUMS`）。

未验证：`top` 交互界面、Python 3.12 以外的解释器版本、Kubernetes 环境、真实生产目标机。

## 参考文档

- py-spy README：https://github.com/benfred/py-spy#readme
- py-spy 发布页：https://github.com/benfred/py-spy/releases/tag/v0.4.2
- 上游 musl 构建流程：https://github.com/benfred/py-spy/blob/v0.4.2/.github/workflows/build.yml
- remoteprocess（libunwind 链接逻辑）：https://github.com/benfred/remoteprocess
- Rust 静态链接 `crt-static`：https://doc.rust-lang.org/reference/linkage.html#static-and-dynamic-c-runtimes
- libunwind：https://github.com/libunwind/libunwind
