# ModelScope 单文件下载工具

无需目标机器安装 Python、pip 或 ModelScope。使用官方下载实现，只提供 `download`、
`login`、`logout`、`whoami`，不提供推理、训练、上传或插件安装，也不包含模型权重。

## 版本与产物

- Python 3.12.15，来自指定的 python-build-standalone **20261021**。
- ModelScope **1.40.2** / modelscope-hub **0.4.6**，PyInstaller **6.22.3**。
- Linux / Windows 依赖分别固定于 `requirements-linux.lock` / `requirements-windows.lock`，使用 SHA256 校验。
- Linux 内置 CentOS 7 的 `libgcc` **4.8.5-44.el7**，RPM 按架构固定 SHA256，避免带入宿主机新版库。
- Linux 启动器使用 Zig **0.15.2** 按 glibc 2.17 目标编译，并静态内置 PyInstaller 源码附带的
  zlib **1.3.2**；不要求目标机器安装 `libz.so.1`。Zig 只用于构建，不进入运行包。
- `dist/linux-amd64/modelscope`：Linux x86_64。
- `dist/linux-aarch64/modelscope`：Linux ARM64。
- `dist/modelscope-linux-<架构>.tar.gz`：上述单文件及说明、版本、校验清单。
- Windows 原生构建输出 `dist/windows-amd64/modelscope.exe` 和 `dist/modelscope-windows-amd64.zip`，
  不能直接用 Linux PyInstaller 交叉生成。

## 使用

复制对应架构的 `modelscope` 一个文件即可运行，不需要旁边放置脚本或依赖。

```bash
chmod +x ./modelscope
./modelscope --version
./modelscope download --help

# 指定文件（不下载模型权重）
./modelscope download Qwen/Qwen2.5-0.5B-Instruct config.json --local-dir ./qwen-config

# 整个仓库：可能很大，执行前注意磁盘空间
./modelscope download Qwen/Qwen2.5-0.5B-Instruct --local-dir ./qwen

# 按模式筛选；必须加引号，避免 shell 展开
./modelscope download Qwen/Qwen2.5-0.5B-Instruct \
  --include '*.json' --exclude 'tokenizer*' --local-dir ./qwen-json

# 数据集下载；--include/文件名根据仓库实际内容填写
./modelscope download --dataset AI-ModelScope/alpaca-gpt4-data-zh \
  --include 'README*' --local-dir ./dataset-readme

# 老版参数也由官方兼容层处理
./modelscope download --model Qwen/Qwen2.5-0.5B-Instruct \
  --local_dir ./qwen-config config.json

# 私有或需授权资源：交互输入 Token，避免进入命令历史
./modelscope login
./modelscope whoami
./modelscope logout
```

也支持 `MODELSCOPE_API_TOKEN` 环境变量；下载私有资源需账号拥有对应权限。
缓存目录可用 `--cache-dir` 指定，保存目录可用 `--local-dir` 指定；版本用 `--revision`。
未指定 `--local-dir` 时使用官方缓存机制。

## 运行要求与取舍

- **不是 musl 纯静态程序**：PyInstaller 内置 Python、OpenSSL、CA 证书和 Python 依赖，
  但 Linux 仍需 glibc 和动态加载器。GNU Python 与依赖 wheels 按 glibc 2.17 基线选择；
  实际验证结果见 `test/VALIDATION.md`，不能仅凭 wheel 标签保证全部旧系统兼容。
- 使用普通 x86_64 指令集版本，不选择 x86_64_v2/v3/v4；Alpine/musl 系统不作为目标。
- Windows 以 Windows 10/11 x64 为目标，内置 Python、VC runtime、下载依赖和 CA 证书，
  仍依赖 Windows 系统 DLL 和系统提供的 UCRT。不保证 Windows 7/8 或旧版 Server 可运行。
  exe 未做代码签名，SmartScreen/杀毒软件可能提示；不关闭安全软件，不要求管理员启动。
- 单文件启动时解压到临时目录，需足够空间及允许加载/执行解压文件。
  `/tmp` 若限制执行，可设置 `TMPDIR` 为有权限的独立目录。
  Windows 使用可写的 `TEMP` / `TMP` 目录；不要把 exe 当作无需解包的纯静态程序。
- 运行需网络访问 ModelScope API 和文件存储服务；自带依赖不代表能离线下载模型。
  已下载内容可以搬到离线机器，但本工具不负责推理或训练。
- HTTPS 默认使用内置 certifi CA；企业代理证书可通过 `REQUESTS_CA_BUNDLE` 指向自有 PEM。
  不关闭 TLS 校验。代理采用 `https_proxy` / `http_proxy` 环境变量。
- `login/logout` 会操作当前用户的官方凭据存储，不在打包目录保存 Token；不要以不必要的高权限运行。
- 使用官方 `modelscope_hub.cli.download.DownloadCommand`，不重写下载协议或全量注册 SDK 插件。
  因此只保留下载和账号命令，不展示无法使用的推理等命令。
- Python 许可及依赖 wheel 许可文本随包内元数据分发；libgcc 的 GPL 和 GCC Runtime Library
  Exception 文本位于包内 `licenses/libgcc`。构建依赖不全部进入运行包。

## 原生构建

在工具目录执行（需要 Bash、curl、tar、sha256sum、rpm2cpio、cpio、strip、readelf）：

```bash
bash ./build.sh
```

脚本自动识别当前 Linux 架构，不安装系统软件，不需要修改 builder。
amd64 和 aarch64 应在相应原生主机各执行一次；缓存、venv、构建目录与产物均按架构隔离。
ARM 主机共享目录路径为 `/root/workspace/mystatictools/scripttools-python/modelscope_static`。
不要同时重复构建同一架构。Python 归档固定 SHA256，pip 仅选择 manylinux2014 二进制 wheel，
安装到工具自己的 `.venv-<架构>`，不会使用仓库已有的虚拟环境。
打包后自动检查主程序和内嵌 ELF 的架构、glibc 符号版本、动态依赖与栈权限；失败则不导出压缩包。
`requirements-bootloader.lock` 单独固定构建启动器所需的 Zig wheel 与哈希，
PyInstaller 源码归档也固定 SHA256。首次构建需额外下载约 90 MB 的编译器。

`modelscope_static.spec` 直接打包 `launcher.py`，不照搬参考工具的外置脚本执行模式，
这样交付才是真正不需外部业务脚本的单文件。

### Windows x64

在 Windows 本地磁盘的工具目录运行，建议普通账号，避免在 SSHFS 上创建 Python/venv/build：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
.\dist\windows-amd64\modelscope.exe --version
.\dist\windows-amd64\modelscope.exe download Qwen/Qwen2.5-0.5B-Instruct config.json --local-dir .\qwen-config
.\.venv-windows-amd64\Scripts\python.exe -X utf8 test\smoke.py dist\windows-amd64\modelscope.exe
```

`ExecutionPolicy Bypass` 仅对当前进程生效，不修改系统执行策略。脚本使用系统 PowerShell、curl、tar，
下载固定哈希的 Windows Python 到 `.cache/python/windows-amd64`，创建独立 `.venv-windows-amd64`，
不安装全局 Python、不需要 Zig 或 Linux libgcc。`modelscope_windows.spec` 单独处理 Windows DLL，
不修改已验证的 Linux 打包配置。构建后自动检查所有内嵌 PE 的 x64 架构及 DLL 依赖。
依赖先从本地 wheel 缓存校验，缺少时才访问 PyPI；Python 归档和 wheels 已齐全时可离线重建。

Windows 的功能测试会只复制 exe 到独立目录，清除 Python/venv 的 PATH，使用独立 HOME、USERPROFILE、
APPDATA 和临时目录，避免使用或清理真实账号凭据；这不等同于在全新 Windows 虚拟机验证。

## 验证方法

在各架构原生主机运行（以下以 amd64 为例，ARM 路径替换为 aarch64）：

```bash
python3 test/smoke.py dist/linux-amd64/modelscope
.venv-amd64/bin/python test/audit_elf.py dist/linux-amd64/modelscope

# 可选：只有 glibc 2.17 的最小容器，无系统 Python、证书、shell、zlib 或 libgcc
docker buildx build --builder default --load -f test/Dockerfile.glibc217 \
  --build-arg TOOL_ARCH=amd64 -t modelscope-static-test:amd64 .
python3 test/isolated.py modelscope-static-test:amd64
```

测试使用独立 HOME、缓存和临时目录，结果保存在 `test/results/`，不混入最终运行包。
模型测试仅下载小配置文件，数据集测试仅下载 README，避免无意拉取大权重。

2026-10-23 已验证：amd64 在 `192.168.188.150`、aarch64 在 `192.168.182.150` 原生构建与测试。
两个架构均通过 12 项功能测试、主程序及全部内嵌 ELF 检查，以及 5 项 glibc 2.17
最小环境测试（没有系统 Python 或 CA 证书）。未验证大权重完整下载、中断恢复、有效账号登录
和用户真实生产环境；完整记录见源码目录的 `test/VALIDATION.md`。

2026-10-24 已在 `liuwenru@192.168.188.3`（Windows x64，NT 10.0.26300.0）原生构建 exe，
通过 31 个 PE 文件的架构/DLL 检查和 13 项功能测试，包含中文带空格保存路径。
exe 约 17 MB，实际仅需复制这一个文件；其他 Windows 版本和全新 Windows 虚拟机尚未实测。

## Reference Documentation

- [ModelScope 固定版本源码与安装说明](https://github.com/modelscope/modelscope/tree/v1.40.2)
- [ModelScope 模型下载说明](https://modelscope.cn/docs/模型的下载)
- [指定 Python 发行版](https://github.com/astral-sh/python-build-standalone/releases/tag/20261021)
- [Python 发行包选择与运行要求](https://gregoryszorc.com/docs/python-build-standalone/main/running.html)
- [Python 归档类型与静态 musl 限制](https://gregoryszorc.com/docs/python-build-standalone/main/distributions.html)
- [PyInstaller 工作方式](https://pyinstaller.org/en/stable/operating-mode.html)
- [PyInstaller Windows 运行库要求](https://pyinstaller.org/en/stable/usage.html#windows)
- [PyInstaller 启动器编译与 static-zlib 选项](https://github.com/pyinstaller/pyinstaller/blob/v6.22.3/bootloader/wscript)
- [CentOS 7 归档仓库（仅取固定 libgcc RPM）](https://vault.centos.org/7.9.2009/os/x86_64/Packages/)
