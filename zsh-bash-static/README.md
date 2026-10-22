# zsh / Bash 纯静态构建

使用 Alpine 3.22 + musl，构建 Linux **amd64/x86_64** 和 **arm64/aarch64** 两种架构：

- zsh **5.9.2**。
- Bash **5.3.20**：5.3 源码加官方 `bash53-001`～`bash53-020` 补丁。
- ncurses **6.5**：自行构建宽字符静态库，内嵌常见终端定义。

两个 ELF 可单独复制运行，目标机不需要 musl、Readline、ncurses、PCRE2、GDBM、libcap 的共享库。
**单二进制不等于完整用户环境**：zsh 高级补全依赖函数文件，外部命令、插件、配置和解释器不包含在二进制中。

## 构建

需要 Docker、默认 buildx。跨架构构建需要宿主机已配置的 binfmt/QEMU；脚本不会创建或切换
builder，不会安装模拟器或修改宿主机构建环境。

```sh
./build.sh                         # 依次构建两种架构
./build.sh amd64 --progress plain
./build.sh aarch64 --progress plain
```

构建时联网，运行时可离线。下载重试 4 次；源码和 Bash 官方补丁逐个验证 SHA-256。
如需代理，可通过 Docker 标准 `--build-arg HTTPS_PROXY=...` / `HTTP_PROXY=...` 传入。

```text
dist/
├── x86_64/
│   ├── bash
│   ├── zsh
│   ├── init.zsh
│   ├── SHA256SUMS
│   ├── bash-config.h
│   ├── zsh-config.h
│   ├── zsh-config.modules
│   ├── build-packages.txt
│   ├── test-results.txt
│   └── share/
│       ├── zsh/functions/     # 官方补全、提示符及其他函数
│       ├── locale/            # 可选 Bash 消息翻译
│       └── licenses/
└── aarch64/                   # 同样的目录结构
```

`BASH_VERSION`、`ZSH_VERSION`、`NCURSES_VERSION` 及相应哈希可用构建参数覆盖。
**升级 Bash 时还必须同步 `bash-patches.sha256` 和版本检查中的补丁级别**，不能只更换压缩包。
Alpine 软件包跟随 3.22 分支仓库更新，不声称传递依赖完全可复现；实际版本见 `build-packages.txt`。

## 离线使用

复制对应架构文件，不要直接覆盖正在使用的系统 shell：

```sh
chmod +x ./bash ./zsh
./bash --noprofile --norc
./zsh -f
```

不带这些隔离参数时，正常读取用户和系统启动文件。已有配置若调用缺失的命令或插件，仍会报错。
注意 zsh `-f` 仍会读取全局 `/etc/zshenv`（若存在），并非无条件跳过所有系统配置。
不要直接更改 root 登录 shell 或 `/bin/sh`；需要设为登录 shell 时，先自行确认绝对路径、
`/etc/shells`、启动文件以及恢复登录方式。

### zsh 完整补全和官方函数

保留 `zsh`、`init.zsh`、`share/zsh/functions/` 的相对布局，在当前 zsh 或 `~/.zshrc` 中加入：

```zsh
source /你的安装目录/init.zsh
```

初始化脚本按自身位置设置 `fpath` 并运行 `compinit`，不修改任何现有配置。
默认保留 `compinit` 的目录权限安全检查，不使用 `compinit -u` 跳过检查。
`HOME` 需可写以保存补全缓存；实际安装时确保目录归当前用户或 root 所有，且不可被其他用户写入。
只有 `zsh` 单文件时，仍有 ZLE、文件名补全、`compctl` 与补全引擎，但没有 `compinit` 和完整命令补全库。

Bash 内置 `complete`、`compgen`、Readline 和文件名补全；GNU Bash 本身不附带通用命令补全脚本。
可按需使用本仓库的 `../bash-completion-lite/`，本项目不会自动加载它。

### 终端定义

ncurses 优先读取目标机 terminfo，没有对应条目时使用内嵌 fallback：

```text
ansi linux vt100 vt102 vt220
xterm xterm-256color xterm-direct
screen screen-256color tmux tmux-256color
rxvt rxvt-256color
alacritty alacritty-direct foot foot-direct xterm-kitty
```

`xterm-kitty` 是 ncurses 官方 kitty 条目的别名，不用不兼容条目冒充其他终端。
其他终端请提供正确的 terminfo，可用 `TERMINFO` / `TERMINFO_DIRS` 指定。
内嵌定义只供这两个 shell 使用，不会替目标机的 vim、less 等程序安装定义。

## 功能与边界

### Bash

- 使用源码自带 Readline，保留行编辑、历史、可编程补全、作业控制、数组、关联数组、正则、
  扩展 glob、进程替换、协进程、网络重定向、内置 `help` 等正常默认功能。
- 不采用 minimal 配置，不将内置帮助拆成外部文件，不改变 extglob 等选项的默认语义。
- 使用 musl 自带的分配器（`--without-bash-malloc`）。Bash 自带分配器依赖可用的 `sbrk`，
  musl 的该接口不支持扩展堆；使用它会导致启动时分配失败。这是分配器替换，不裁剪 shell 功能。
- 保留 NLS 构建支持。`share/locale/` 中消息目录为可选资源；Bash 编译的查找路径为
  `/usr/local/share/locale`，不会自动查找二进制旁的目录。musl 不提供 glibc 的完整 locale
  行为和 locale 数据库，不承诺中文诊断消息或与 glibc 一致的排序；建议 `LANG=C.UTF-8`。
- musl 纯静态程序不能 `dlopen` 外部 `.so`；因此 Bash `enable -f` 动态内建扩展不可用。
  不将这个限制伪装为可用功能，也不额外编入全部示例内建来改变命令集合。

### zsh

- 禁止动态加载，将源码中的模块静态链接进主程序，仍使用正常的 `zmodload` 接口激活。
  具体清单见 `zsh-config.modules`，测试逐一激活静态模块，防止只写配置而没有实际功能。
- 保留 ZLE、complete/compctl/complist、PCRE2 与 POSIX 正则、GDBM、capabilities、curses、
  terminfo/termcap、TCP/Unix socket、zpty、文件操作、stat、mapfile、mathfunc、datetime、
  zselect、zprof 等模块，并启用 Maildir 检测。GDBM 使用 Alpine 提供的静态库。
- 外部第三方二进制 `.so` 模块不可用；纯 zsh 脚本插件仍可自行提供，其外部依赖需另行安装。
- `zftp` 是传统 FTP 客户端，不是 TLS/SFTP 客户端。`watch` 等依赖 utmp 的功能受 musl 和目标机
  记账设施限制，模块存在不代表目标机提供用户登录记录。新用户配置向导等脚本功能需对应资源。

### 共同运行依赖

- Linux 内核、正确的架构和执行权限；交互模式需真实终端，PTY 通常依赖 `/dev/pts`。
- 作业控制需要内核进程组/信号支持；网络功能需要 socket 权限和网络配置。
- 进程替换通常需要 `/dev/fd`（常链接至 `/proc/self/fd`）、`/proc` 或系统相应设施。
- 用户/组名称、主目录解析可能需要 `/etc/passwd`、`/etc/group`；DNS 需要正确的
  `/etc/resolv.conf`、`/etc/hosts`，musl 不使用 glibc NSS 插件。
- 历史文件、补全缓存、临时文件需要相应目录可写。
- `ls`、`grep`、`ssh`、`git`、`sudo` 等仍是外部程序；脚本的 shebang 如写死 `/bin/bash`，
  不会自动指向随身携带的这个二进制，应显式使用 `./bash script.sh`。

## 验证

每种架构导出前必须通过：

1. `file` 与 `readelf` 检查 ELF 架构，确认没有 `INTERP` 或 `NEEDED`。
2. 精确检查 Bash 5.3.20、zsh 5.9.2 版本。
3. 空根目录 chroot，只放两个 ELF 和最小用户信息，无共享库、外部命令或 terminfo，验证
   Unicode、数组、正则、管道、后台任务、信号，以及 zsh PCRE2、GDBM 持久化等。
4. 构建容器移除磁盘 terminfo 后，在真实 PTY 中测试 7 种终端的退格编辑、Tab 补全、中文输出、
   前台任务挂起、`jobs`、`fg` 和 Ctrl-C，并测试 zsh curses 初始化。
5. 测试进程替换、Bash 协进程、所有静态 zsh 模块、可搬迁的 `compinit`/git 补全注册、
   仅环回网络上的 Bash `/dev/tcp` 和 zsh `ztcp`。

测试用独立 HOME、配置和临时目录，不修改宿主机 terminfo，不连接已有服务。
amd64 在当前 x86_64 宿主机原生执行；aarch64 经宿主机已有模拟器执行，
**不能代替真实 aarch64 目标机验证**。这些是关键功能冒烟测试，不等于全部上游测试或全部插件兼容性测试。

补充执行的 amd64 上游回归存在 locale、纯静态限制和测试环境相关差异，**并非全绿**；
具体结果、尚未逐项确认的差异及复现方式见 [VERIFICATION.md](VERIFICATION.md)。

## Reference Documentation

- [GNU Bash 官方源码](https://ftp.gnu.org/gnu/bash/)
- [Bash 5.3 官方补丁](https://ftp.gnu.org/gnu/bash/bash-5.3-patches/)
- [Bash 编译可选功能](https://www.gnu.org/software/bash/manual/html_node/Optional-Features.html)
- [zsh 官方发布与 SHA256SUM](https://www.zsh.org/pub/)
- [zsh 安装说明](https://github.com/zsh-users/zsh/blob/zsh-5.9.2/INSTALL)：重点为 Dynamic loading、Adding and removing modules。
- [zsh 模块手册](https://zsh.sourceforge.io/Doc/Release/Zsh-Modules.html)
- [ncurses 源码](https://invisible-mirror.net/archives/ncurses/)：`INSTALL` 中的 `CONFIGURING FALLBACK ENTRIES`。
- [musl 功能差异](https://wiki.musl-libc.org/functional-differences-from-glibc.html)

源码版本与校验固定在 Dockerfile / `bash-patches.sha256`，构建配置随产物保存。
对外分发二进制时需履行 Bash/GDBM 的 GPL 以及 musl、ncurses、PCRE2、libcap、gettext 等依赖的许可证义务，
包括适用的版权声明和对应源码提供要求；仅提供上游下载链接不能替代所有合规义务。
