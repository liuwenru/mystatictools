# Linux 验证记录

日期：2026-10-27。两个架构都在对应架构的原生主机上构建和测试，没有使用 QEMU。
共享目录为 SSHFS，两端路径都是 `/root/workspace/mystatictools/scripttools-python/benchmark_response_stats`。

## amd64

- 构建主机：`192.168.188.150`，x86_64。
- 产物：`dist/linux-amd64/benchmark_response_stats`，15,352,792 字节。
- SHA256：`4016b1e245d5814c4af56c89bb0cbc712841110df9cea2d6c8e47755cc2c55d9`。
- `test/results/elf-x86_64-hlhleeit/summary.json`：主程序和 2 个内嵌 ELF 全部是 x86_64，GLIBC 符号最高 2.17，
  栈不可执行，NEEDED 只有 glibc 自带库，启动器不依赖 `libz.so.1`。
- `test/results/smoke-x86_64-a04w_92d/summary.json`：12 项通过。
- `test/results/isolated-x86_64-tmfl6xg7/summary.json`：glibc 2.17 最小容器中 4 项通过。

## aarch64

- 构建主机：`192.168.182.150`，aarch64。
- 产物：`dist/linux-aarch64/benchmark_response_stats`，13,531,944 字节。
- SHA256：`ac35f09beec9f5d62c72eaeb7078e86437a6c25604316c6e684e92ad1e3c8e31`。
- `test/results/elf-aarch64-kchf8nkz/summary.json`：主程序和 3 个内嵌 ELF 全部是 AArch64，GLIBC 符号最高 2.17，
  动态解释器为 `/lib/ld-linux-aarch64.so.1`。内嵌的 `libgcc_s.so.1` 来自固定的 CentOS 7 RPM。
- `test/results/smoke-aarch64-pjq31dpm/summary.json`：12 项通过。
- `test/results/isolated-aarch64-tm7ndad3/summary.json`：glibc 2.17 最小容器中 4 项通过。

两个架构的压缩包都核对了文件清单和 SHA256SUMS，没有混入测试目录或虚拟环境。

## 测试内容

`test/smoke.py`：只把可执行文件和脚本复制到独立目录，环境变量只保留 PATH、HOME、TMPDIR，不设置 LANG。

- 帮助信息为中文；1..100 样本的平均值、中位数、P95/P99 和长尾指标与手算值一致。
- 与测试机系统 Python 直接运行同一脚本，stdout/stderr 完全一致。
- `LANG=C` 下中文 URL 正常输出；从其他目录用相对路径运行；经符号链接调用能找到脚本。
- 输入不存在、没有有效记录、缺少参数、非 UTF-8 输入时退出码为 2；缺少外置脚本时退出码为 1。
- 不重新构建，直接把外置脚本替换为另一个脚本：sqlite3、ssl、lzma、bz2、zlib、ctypes、
  concurrent.futures、xml、email 等标准库都能用，Python 版本为 3.12.15，中文参数原样传入。

`test/isolated.py`：`test/Dockerfile.glibc217` 只包含 CentOS 7 的 glibc 2.17 运行库，没有 Python、shell、
zlib、libgcc 和 locale 数据。运行时断网、只读根文件系统、非 root、去掉所有 capability。
测试帮助、统计、输入不存在，以及替换脚本后的标准库检查。容器共享宿主内核。

## 构建中发现的问题

- 收集完整标准库时，`_tkinter` 带进了 tcl/tk 库，`_crypt` 依赖没有随包的 `libcrypt.so.1`。
  两者都已排除；`audit_elf.py` 增加了 NEEDED 白名单检查，防止以后再混入。
- aarch64 版 libpython 依赖 `libgcc_s.so.1`，首次构建时打包了 ARM 构建机的 libgcc（要求 GLIBC_2.35），
  被 ELF 检查拦下。现在改用固定的 CentOS 7 libgcc 4.8.5。
- 共享目录的 SSHFS 不支持 readlink，ARM 主机上在共享目录里建的符号链接无法执行。
  这是测试环境的问题，测试改为在本地临时目录建链接。

## 尚未验证

- CentOS 7 原始内核（3.10）和真实目标机器。
- 很大的输入文件（数据会全部读入内存，内存占用和数据量成正比）。
- `/tmp` 为 noexec 时使用 `TMPDIR` 绕过（README 中有说明，未实测）。
