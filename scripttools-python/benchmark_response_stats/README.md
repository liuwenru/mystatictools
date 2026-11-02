# benchmark_response_stats 响应时间统计工具

读取"URL、服务器、响应时间"三列文本，分别按 URL 和服务器统计 count、平均值、中位数、
P95/P99 及长尾（最慢 1%/5%）影响。目标机器不需要安装 Python。

## 版本与产物

- Python 3.12.15，来自指定的 python-build-standalone **20261021**，归档固定 SHA256。
- PyInstaller **6.22.3**；构建依赖固定在 `requirements-build.lock`，使用 SHA256 校验。
- Linux 启动器使用 Zig **0.15.2** 按 glibc 2.17 目标重新编译，并静态链接 PyInstaller 源码附带的
  zlib **1.3.2**，不要求目标机器有 `libz.so.1`。Zig 只用于构建，不进入运行包。
- aarch64 额外内置 CentOS 7 的 `libgcc` **4.8.5-44.el7**（RPM 固定 SHA256）。原因是 aarch64 版 libpython
  本身依赖 `libgcc_s.so.1`；不固定的话，PyInstaller 会打包构建机的新版 libgcc（实测要求 GLIBC_2.35），
  在旧系统上无法加载。x86_64 版 libpython 没有这个依赖，所以不带。
- `dist/linux-amd64/`：x86_64；`dist/linux-aarch64/`：ARM64。
- `dist/benchmark_response_stats-linux-<架构>.tar.gz`：可执行文件、统计脚本、说明、构建信息、校验清单。

## 使用

运行包是**两个文件**，必须放在同一目录：

```text
benchmark_response_stats      # 内置 Python 的启动程序
benchmark_response_stats.py   # 统计逻辑，每次运行时从可执行文件同目录读取
```

```bash
tar xzf benchmark_response_stats-linux-amd64.tar.gz
cd benchmark_response_stats-linux-amd64
./benchmark_response_stats --help
./benchmark_response_stats access.txt
```

输入按空白分隔，第一列 URL，第二列服务器，第三列响应时间。空行会忽略；列数不足或时间不是数字的行
会跳过，并在 stderr 给出行号。统计结果输出到 stdout，汇总行输出到 stderr，方便重定向。
输入文件必须是 UTF-8。

## 为什么用外置脚本

启动程序通过 `runpy` 执行同目录下的 `benchmark_response_stats.py`，并不执行打包时内嵌的那份副本。
这样**修改统计逻辑不需要重新构建**，直接替换 `.py` 即可。通过符号链接调用时，会解析到真实路径所在目录找脚本。

为了让改过的脚本也能用新的标准库模块，打包时带入了**完整标准库**，代价是体积比只打包用到的模块大。
sqlite3、ssl（内置 OpenSSL 3.5.9）、lzma、bz2、ctypes、multiprocessing 等都可以直接使用，
`test/smoke.py` 会实际替换脚本来验证。以下模块没有打包：

- tkinter、turtle、idlelib：要 tcl/tk 和图形界面，命令行工具用不上。
- test、ensurepip、venv、lib2to3：测试集和打包工具，冻结后的程序里用不了。
- crypt：Python 3.12 已弃用、3.13 删除；它依赖系统的 `libcrypt.so.1`，PyInstaller 不打包这个库，
  而 RHEL 9 / Fedora 默认没有。需要密码哈希时改用 `hashlib`。

其他限制：
- 只能用标准库。新增第三方包需要先加入 `requirements-build.lock` 和 spec，再重新构建。
- `zoneinfo` 没有内置 tzdata，目标机器没有 `/usr/share/zoneinfo` 时无法使用时区数据库。
- `dbm.gnu` 不可用（python-build-standalone 没有编译 gdbm），`dbm` 会改用 `dbm.ndbm` / `dbm.dumb`。
- 脚本必须兼容 Python 3.12。原来用 3.15 构建，现在改为与 `../modelscope_static` 相同、已经验证过的
  3.12.15 归档；现有统计脚本只用基础标准库，在两个版本下输出一致。

## 运行要求与取舍

- **不是 musl 纯静态程序**：需要 glibc 和动态加载器（`ld-linux-x86-64.so.2` / `ld-linux-aarch64.so.1`），
  依赖 libc、libdl、libm、libpthread、librt、libutil，这些都是 glibc 自带的库。
  没有走 Alpine/musl 路线，原因是 PyInstaller 需要动态加载 libpython 和扩展模块；
  python-build-standalone 的 musl 版本是完全静态的，不支持加载扩展模块（见参考文档）。
- glibc 最低 2.17（CentOS 7、Ubuntu 14.04、Debian 8 及以后版本）。启动器和所有内嵌 ELF 的 GLIBC 符号版本由
  `test/audit_elf.py` 检查，不超过 2.17；它同时检查 NEEDED 只包含 glibc 自带库或包内已有的库。
  glibc 只能向前兼容，CentOS 6（glibc 2.12）等更老的系统无法运行。
- x86_64 使用基础指令集，不要求 x86_64-v2/v3。Alpine/musl 系统不作为目标。
- 单文件启动时会解压到临时目录，需要可写、可执行的临时空间。`/tmp` 如果挂了 noexec，
  可以设置 `TMPDIR` 指向一个允许执行的目录。
- 不需要网络、CA 证书、locale 数据或终端定义。在 `LANG=C` 下也能正常输出中文 URL。
- Python、PyInstaller、zlib 和 libgcc（aarch64）的许可文本随包放在内嵌的 `licenses/` 目录。

## 构建

在工具目录执行（需要 Bash、curl、tar、sha256sum、readelf）：

```bash
bash ./build.sh
```

脚本按当前机器架构构建，不安装系统软件，不使用宿主机的 Python 或 venv，也不需要修改 libpython 的
execstack（python-build-standalone 的 libpython 栈本来就不可执行）。
amd64 和 aarch64 要分别在对应架构的原生主机上执行，缓存、venv、构建目录和产物都按架构分开。
同一架构不要在两台机器上同时构建。打包后会自动做 ELF 检查，检查失败就不生成压缩包。

## 验证

```bash
python3 test/smoke.py dist/linux-amd64/benchmark_response_stats
.venv-amd64/bin/python test/audit_elf.py dist/linux-amd64/benchmark_response_stats

# 只有 glibc 2.17 的最小容器：没有 Python、shell 和 zlib，断网运行
docker buildx build --builder default --load -f test/Dockerfile.glibc217 \
  -t benchmark-stats-glibc217:amd64 .
python3 test/isolated.py benchmark-stats-glibc217:amd64 dist/linux-amd64
```

测试结果保存在 `test/results/`，不进入运行包。两个测试都把可执行文件和脚本复制到独立目录，不使用构建 venv、
宿主 locale 或用户 HOME。

2026-10-27 已验证：amd64 在 `192.168.188.150`、aarch64 在 `192.168.182.150` 原生构建与测试，
不使用 QEMU。两个架构都通过 ELF 检查、12 项功能测试和 4 项 glibc 2.17 最小容器测试。
容器共享宿主内核，未在 CentOS 7 原始内核和真实目标机器上运行。完整记录见 `test/VALIDATION.md`。

## Reference Documentation

- [python-build-standalone 20261021](https://github.com/astral-sh/python-build-standalone/releases/tag/20261021)
- [Python 发行包运行要求（glibc 版本）](https://gregoryszorc.com/docs/python-build-standalone/main/running.html)
- [Python 归档类型与静态 musl 限制](https://gregoryszorc.com/docs/python-build-standalone/main/distributions.html)
- [PyInstaller 工作方式](https://pyinstaller.org/en/stable/operating-mode.html)
- [PyInstaller 启动器编译与 static-zlib 选项](https://github.com/pyinstaller/pyinstaller/blob/v6.22.3/bootloader/wscript)
- [CentOS 7 归档仓库（仅取固定 libgcc RPM）](https://vault.centos.org/altarch/7.9.2009/os/aarch64/Packages/)
- [Python runpy 模块](https://docs.python.org/3.12/library/runpy.html)
