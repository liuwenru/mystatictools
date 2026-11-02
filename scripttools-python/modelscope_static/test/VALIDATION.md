# Linux / Windows 验证记录

日期：Linux 2026-10-23，Windows 2026-10-24。所有运行均为对应架构原生执行，未使用 QEMU 或 Wine。

## amd64

- 构建主机：`192.168.188.150`，x86_64，宿主 glibc 2.43。
- 产物：`dist/linux-amd64/modelscope`，21,162,696 字节。
- SHA256：`c2262c26f24588de281f3ffd36a9a309423388c5f77d6b18755eaa49ff2a8e71`。
- `test/results/smoke-x86_64-1nl84s2o/summary.json`：12 项通过。
  覆盖版本、帮助、无效命令、空 Token 拒绝、隔离账号退出、旧参数、模型单文件、
  不存在文件的非零退出码、快照筛选、数据集单文件、指定缓存及重复下载。
- `test/results/elf-x86_64-cujp3a_v/summary.json`：主程序与 6 个内嵌 ELF 全部为 x86_64，
  所需 GLIBC 符号最高 2.17，栈不可执行。启动器不依赖外部 zlib。
- `test/results/isolated-x86_64-yee21rfk/summary.json`：5 项通过。
  glibc 2.17 scratch 容器中，断网版本/帮助，以及联网模型、筛选快照、数据集下载均通过。

## aarch64

- 构建主机：`192.168.182.150`，aarch64，宿主 glibc 2.43。
- 产物：`dist/linux-aarch64/modelscope`，19,438,592 字节。
- SHA256：`202a5a00a06b1c5e4259724d98b4b3ef3664074aa91f4be0f572aa0a92795610`。
- `test/results/smoke-aarch64-zjii2ueb/summary.json`：与 amd64 相同的 12 项测试全部通过。
- `test/results/elf-aarch64-8wdn4egd/summary.json`：主程序与 6 个内嵌 ELF 全部为 AArch64，
  所需 GLIBC 符号最高 2.17，栈不可执行。启动器不依赖外部 zlib，
  动态解释器为 AArch64 GNU ABI 的 `/lib/ld-linux-aarch64.so.1`。
- `test/results/isolated-aarch64-6hm3xmw0/summary.json`：与 amd64 相同的 5 项最小环境测试全部通过。

两个架构的压缩包均核对了内部文件清单、二进制内容和 SHA256，未混入测试目录或虚拟环境。

## Windows x64

- 构建主机：`liuwenru@192.168.188.3` / `DESKTOP-ACQ3DOR`，Windows NT 10.0.26300.0，PowerShell 5.1。
- Windows 本地工作目录：`C:\Users\liuwenru\buildtools\modelscope_static`，未使用 SSHFS 构建。
- Python 3.12.15 使用指定发行版 `20261021` 的 Windows MSVC 包，归档 SHA256 固定。
- 产物：`dist/windows-amd64/modelscope.exe`，17,056,929 字节。
- SHA256：`c20071760edd660cf7bc5330823b60685ec0a59494086f0221391863fedd617d`。
- `test/results/pe-windows-amd64-c_0tjc54/summary.json`：31 个 PE 全部为 AMD64/PE32+，
  导入依赖可在包内或 Windows System32/API sets 中解析；Python、VC runtime 和 certifi CA 已内置。
- `test/results/smoke-Windows-AMD64-sgjtzxi9/summary.json`：13 项全部通过。
  覆盖与 Linux 相同的 12 项功能，加上中文带空格的保存路径。
- 测试只复制 exe 到独立目录，PATH 只保留 System32，移除 venv/Conda 提示，
  使用独立 USERPROFILE、HOME、APPDATA、LOCALAPPDATA 和 TEMP/TMP，未操作真实账号凭据。
- 使用普通控制台启动器，不要求 UAC 提权；未安装全局 Python、修改 SSH 或系统执行策略。
  `ExecutionPolicy Bypass` 只用于构建进程。
- Windows 适配后的公共测试脚本再次在 Linux amd64 回归，12 项全部通过：
  `test/results/smoke-Linux-x86_64-4kclxgwe/summary.json`。两个 Linux 二进制 SHA256 未改变。

Windows 测试并非干净系统虚拟机；仍使用本机提供的 Windows 系统 DLL/UCRT。
未验证旧版 Windows/Server，也未对 exe 代码签名。

## 最小环境的边界

`test/Dockerfile.glibc217` 只从固定 CentOS 7 镜像提取 glibc 及 DNS/NSS 库，加入程序和
`nsswitch.conf`。没有系统 Python、shell、pip、CA 证书、zlib 或 libgcc。
运行时使用非 root 用户、只读根文件系统、独立 tmpfs 和测试输出目录。
Docker 构建只使用默认 builder，不安装模拟器。

这证明单文件自带下载所需的 Python、TLS 证书及非 glibc 依赖，**不代表纯静态链接**。
容器仍共享宿主内核，未在 CentOS 7 原始内核及用户真实生产环境验证。

## 尚未验证

- 大模型完整权重、超大文件中断恢复、长时间下载稳定性。
- 有效账号登录、私有或受限资源（未使用用户凭据）。
- 企业代理自签 CA、Alpine/musl、其他 Windows 版本及全新 Windows 虚拟机。

测试下载的是 Qwen/Qwen2.5-0.5B-Instruct 的配置文件，以及
AI-ModelScope/alpaca-gpt4-data-zh 的 README，不包含模型权重和完整数据集。
