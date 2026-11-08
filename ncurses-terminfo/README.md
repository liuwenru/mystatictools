# ncurses-terminfo 6.6：静态 tic/infocmp + 终端定义包

用来解决远程维护时的这类报错：`unknown terminal type`、`'xterm-kitty': unknown terminal type`、
`tput: unknown terminal "tmux-256color"`，以及 vim/less/htop 显示错乱、按键不对。
这些问题的原因是目标机的 terminfo 数据库里没有本地终端的定义。

下载对应架构的包，解压后即可使用，**目标机不需要安装 ncurses-bin/ncurses-term**：

- 静态的 `tic`、`infocmp`、`toe`、`tput`、`clear`、`tset`/`reset`（以及 `captoinfo`、`infotocap` 软链接）。
- ncurses 6.6 官方的完整 `terminfo.src`（1861 个条目），以及预编译好的数据库 `share/terminfo/`。
- `install.sh`：把需要的条目编译到 `~/.terminfo` 或系统目录。

ncurses 6.6（2025-12-30，经 invisible-mirror.net 归档页核实为当前最新版本），Alpine 3.22 + musl
从源码静态构建。支持 Linux x86_64 / aarch64，程序没有动态解释器和 NEEDED 依赖。

## 使用

```sh
tar -xzf ncurses-terminfo-6.6-linux-x86_64.tar.gz
cd ncurses-terminfo

./install.sh tmux-256color xterm-kitty           # 装到 ~/.terminfo，当前用户长期有效
./install.sh -o /usr/share/terminfo foot         # root 装到系统目录，所有用户（含 sudo 后）可用
./install.sh -l | grep -i ghostty                # 查包内有哪些条目（含别名）
./install.sh -a                                  # 全部条目装到 ~/.terminfo（约 2 MB）

export TERMINFO_DIRS=$PWD/share/terminfo:        # 不安装，只在当前 shell 临时使用
```

`TERMINFO_DIRS` 末尾的冒号（空项）表示继续查系统默认目录（ncurses 手册的约定）。不同版本的 ncurses
在不加冒号时行为不同，加上更稳妥。

### 远程维护时一键下载安装

root 登录后粘贴执行。会补装当前 `$TERM`（ssh 会把本地终端名带过去）和 tmux-256color：

```sh
if [[ -n $BASH_VERSION ]];then set +o history;shopt -s expand_aliases; fi
if command -v curl >/dev/null 2>&1; then alias downloader='curl -k -L -o'; fi
if command -v wget >/dev/null 2>&1; then alias downloader='wget --no-check-certificate -q -O '; fi
BASEURL=https://fdoc.epoint.com.cn:3366/tmp/.liuwenru/
BB=/usr/local/bin/busybox; [[ -f $BB ]] || BB=/usr/bin/busybox; [[ -f $BB ]] && alias tar="$BB tar"; unset BB
downloader /tmp/terminfo.tar.gz ${BASEURL}/tools/ncurses-terminfo/ncurses-terminfo-6.6-linux-$(uname -m).tar.gz && tar -zxf /tmp/terminfo.tar.gz -C /usr/local && rm -f /tmp/terminfo.tar.gz
for t in $TERM tmux-256color; do d=${t:0:1}/$t; [[ -e /etc/terminfo/$d || -e /lib/terminfo/$d || -e /usr/share/terminfo/$d ]] || /usr/local/ncurses-terminfo/install.sh -o /usr/share/terminfo $t; done; unset t d
if [[ -n $BASH_VERSION ]];then set -o history; fi
```

- 包解压到 `/usr/local/ncurses-terminfo/`，之后可以直接用里面的 `install.sh`、`bin/infocmp`。
- 装到 `/usr/share/terminfo`：这是所有工具都会查的目录。`static_tools` 中的 iftop、nethogs、tcptrack
  自带的静态 ncurses 只查这个系统目录，不查 `/etc/terminfo`，见下文"运行依赖与行为"。
- 系统已有的条目跳过不装，不会覆盖发行版文件；包里没有的条目只报一行错，不影响其他条目。
  重复执行不会重复安装。以后如果安装了 ncurses-term 等包，rpm/dpkg 会用发行版的同名文件替换，不影响使用。
- 之前按旧版 snippet 装到 `/etc/terminfo` 的机器，再执行一次
  `/usr/local/ncurses-terminfo/install.sh -o /usr/share/terminfo tmux-256color`（以及其他需要的条目）即可。
- 已在 CentOS 7、Ubuntu 16.04 容器中验证，下载这一步用本地复制代替。
  CentOS 7 容器中实际下载过：x86_64 原样执行，aarch64 在 ARM 主机上原生执行，下载参数只改成了不显示进度。

### 用本地终端自己的定义（推荐用于 kitty、ghostty、wezterm 等）

终端程序自带的 terminfo 可能比 ncurses 收录的版本新。在**本地机器**上导出，再拿到目标机上编译：

```sh
infocmp -x "$TERM" > "$TERM.src"                 # 本地，-x 保留扩展能力
./install.sh -f xterm-kitty.src                  # 目标机，用包内 tic 编译
```

`infocmp` 输出的是展开后的完整条目，不含 `use=` 引用，单个文件即可编译。
直接把本地编译好的二进制文件复制过去容易出问题，原因见下一节，所以要传源文件、到目标机上重新编译。

## 为什么用传统格式（主要取舍）

ncurses 6.1 起，默认构建的 tic 遇到超过 32767 的数值（如 `pairs#0x10000`、`colors#0x1000000`）时，
会写出**扩展数值格式**（magic `01036`）。ncurses 6.0 及更早版本（CentOS 7、Ubuntu 16.04 等）
读不了这种格式，会报 unknown terminal。这也是"从新机器复制 `/usr/share/terminfo/t/tmux-256color`
到老机器不能用"的原因。

本包按窄字符方式构建 ncurses（`--disable-widec`，此时不启用 ext-colors）。tic 只写**传统格式**
（magic `0432`），超过 32767 的数值截断为 32767：

| 影响 | 说明 |
| --- | --- |
| `pairs` 65536 → 32767 | 256 色终端的颜色对数量；程序很少用到 3 万个以上的颜色对，实际无影响 |
| `*-direct` 条目的 `colors` 16777216 → 32767 | 直接色（真彩色）条目在本包中表现不正确；需要真彩色时用 256 色条目，再配合程序自身的 truecolor 设置（如 tmux `Tc`/`RGB`、vim `termguicolors`） |
| tic 编译时提示 `limiting value of 'pairs'` | 说明发生了截断，不是错误。按名称或 `-a` 安装时 install.sh 不显示这些提示，`-f` 时照常显示 |

扩展能力（`-x`，如 tmux-256color、xterm-kitty 中的 `Smulx`、`Ss`/`Se`）不受影响，会完整保留。
新系统同样能读传统格式。

## 运行依赖与行为

- 安装后读取 terminfo 的是**各程序自己链接的 ncurses**（vim、less、htop、tmux 等），不是包内程序。
  已验证 CentOS 7（ncurses 5.9）、Ubuntu 16.04（ncurses 6.0）的系统程序能读本包生成的文件。
- **系统级安装用 `-o /usr/share/terminfo`，不要用 `/etc/terminfo`。** 系统 ncurses 两个目录都查，
  但静态编译的程序只查编译时写入的目录。对 `static_tools` 中二进制的检查结果：

  | 程序 | 编译进去的系统目录 |
  | --- | --- |
  | iftop、nethogs、tcptrack | 只有 `/usr/share/terminfo` |
  | htop | `/etc/terminfo:/usr/share/terminfo:/lib/terminfo:/usr/lib/terminfo` |
  | tmux、zsh、bash、pstree（本仓库构建） | `/etc/terminfo:/lib/terminfo:/usr/share/terminfo` |

  在 CentOS 7 容器的伪终端中实测（x86_64、aarch64 均原生测试）：tmux-256color 只装在 `/etc/terminfo` 时，
  iftop、nethogs、tcptrack 报 `Error opening terminal: tmux-256color`；装到 `/usr/share/terminfo` 后三者都正常进入界面。
- `~/.terminfo` 只对当前用户有效。`sudo`、`su` 后通常换成 root 的 HOME，setuid 程序也会忽略
  `TERMINFO`、`TERMINFO_DIRS` 和 `~/.terminfo`。这些情况请用 `-o /usr/share/terminfo` 做系统级安装。
- 设置了 `TERMINFO` 环境变量时，install.sh 默认装到该目录。
- 不使用 terminfo 的程序（如 busybox 的 vi/less，它们写死了 VT100 序列）不受本包影响。
- 包内的 `tput`、`clear`、`reset` 和系统命令同名，所以本包不放进 `static_tools/<架构>/`。
  需要时用路径调用，例如 `bin/reset`。
- terminfo 别名是**相对软链接**，解压到任意目录都能用。tar.gz 中的文件属主统一为 root。

### 别名补充

kitty、ghostty 实际设置的 `TERM` 是 `xterm-kitty`、`xterm-ghostty`，但 ncurses 中的条目名是
`kitty`、`ghostty`（内容来自终端上游）。构建时给这两个条目补上了实际的 TERM 名作为别名，
与本仓库 tmux、pstree-static 的处理一致。Dockerfile 会先检查上游没有这两个名字再修改。
除此之外，`terminfo.src` 与官方原文相同。

## 构建和产物

需要 Docker、默认 buildx，构建需要联网。默认只构建当前主机架构：

```sh
./build.sh amd64 --progress plain       # 本机 x86_64
./build.sh aarch64 --progress plain     # 在 192.168.182.150 原生执行
```

脚本不创建、修改或切换 builder，不安装模拟器。共享目录下不要在两台机器上并发构建同一架构。

产物中有 1043 个软链接。ARM 主机通过 SSHFS 访问 `dist/`，而 buildx 的 `type=local` 导出
对软链接执行 lchown 会失败。所以 build.sh 与 node-static 相同：先用 `type=tar` 导出到本机临时目录
打包，再把 tar.gz 复制进 `dist/`，并用 `--no-same-owner` 解压一份到 `dist/<架构>/` 供检查。
在 ARM 主机上经 SSHFS 查看 `dist/aarch64/` 时，软链接会显示为失效，在 x86_64 主机的原生磁盘上是正常的。
以 tar.gz 为准。

```text
dist/
├── ncurses-terminfo-6.6-linux-x86_64.tar.gz(.sha256)    # 约 1.4 MB
├── ncurses-terminfo-6.6-linux-aarch64.tar.gz(.sha256)   # 约 1.5 MB
├── x86_64/ncurses-terminfo/        # 解压结果
└── aarch64/ncurses-terminfo/
```

包内结构：

```text
ncurses-terminfo/
├── bin/          # tic infocmp toe tput clear tset，reset/captoinfo/infotocap 为软链接
├── share/terminfo.src
├── share/terminfo/   # 预编译数据库，传统格式
├── install.sh
├── COPYING.ncurses   # MIT 风格许可
└── SHA256SUMS        # 不含 share/terminfo/ 下的文件
```

程序大小：x86_64 每个 170–320 KB，aarch64 每个 200–330 KB。

### 固定版本与校验

| 组件 | 来源 | SHA-256 |
| --- | --- | --- |
| ncurses-6.6.tar.gz | invisible-mirror.net | `355b4cbb…ff11`（与 pstree-static 相同，完整值见 Dockerfile） |

Alpine 依赖（build-base、musl）随 3.22 分支仓库更新，未锁定版本，本次构建镜像为 Alpine 3.22.6。
升级 ncurses 时同步修改 Dockerfile 中的版本和哈希，以及 `pushfdoc.sh` 中的文件名。

### configure 选项说明

- `--disable-widec`：输出传统格式，原因见上文。包内程序只处理终端描述，不涉及宽字符显示，所以不受影响。
- `--enable-symlinks`：别名用软链接，不用硬链接。
- `--disable-db-install`：不使用 make 安装数据库，由 Dockerfile 用刚构建的 tic 单独编译。
- `cf_cv_multiuser=yes`：构建容器中没有普通用户时，configure 会让 root 忽略 `TERMINFO`、
  `TERMINFO_DIRS`、`~/.terminfo`，这里与发行版 ncurses 保持一致。
- 没有内嵌 fallback 条目：数据库就在包里，用 `TERMINFO_DIRS` 指向它即可。

## 验证

构建阶段（x86_64 在本机原生，aarch64 在 192.168.182.150 原生）必须通过以下检查才导出：

1. 6 个程序的 `file`、`readelf -h` 架构；`readelf -l` 无 `INTERP`，`readelf -d` 无 `NEEDED`；`tic -V` 为 6.6。
2. 删除构建容器中的全部系统 terminfo 后运行 `test/smoke-test.sh`：
   - 预编译的 1859 个文件全部为传统格式，tmux-256color 的 pairs 为 0x7fff；别名是相对软链接，没有失效链接。
   - 包内 `tput`/`clear`/`infocmp` 通过 `TERMINFO_DIRS` 读取 tmux-256color、xterm-kitty、xterm-ghostty、
     xterm-256color、linux，输出的转义序列正确。
   - `install.sh`：按名称装到 `~/.terminfo` 后能读取（root 身份）；用 `-o` 时只写入所列条目，内容与包内一致；
     `-f` 安装 `infocmp -x` 导出的文件后内容不变；未知终端名、相对路径会报错；`-l` 能列出别名。
   - `infocmp -C`、`infotocap`、`toe` 正常。

在老发行版上验证（`test/old-system-test.sh`，x86_64、aarch64 分别在对应主机上原生运行，容器断网）：

| 系统 | 系统 ncurses | 系统 tput 读取包内 6 个条目 | install.sh 安装后系统程序可读 | 对照：宿主机编译的 tmux-256color |
| --- | --- | --- | --- | --- |
| CentOS 7 | 5.9 | 通过 | 通过 | 读取失败（扩展格式） |
| Ubuntu 16.04 | 6.0 | 通过 | 通过 | 读取失败（扩展格式） |

测试的 6 个条目为 tmux-256color、xterm-kitty、xterm-ghostty、foot、alacritty、wezterm。

**未验证**：真实的老系统物理机或虚拟机（以上测试使用容器，内核是宿主机的。本包不依赖内核特性）；
各终端模拟器里的实际显示效果；BSD、macOS（目录结构不同，本包只面向 Linux）。

## Reference Documentation

- [ncurses 官方主页](https://invisible-island.net/ncurses/)
- [ncurses 下载归档](https://invisible-mirror.net/archives/ncurses/)
- [ncurses 安装说明（configure 选项）](https://invisible-island.net/ncurses/INSTALL.html)
- [ncurses FAQ](https://invisible-island.net/ncurses/ncurses.faq.html)
- [tic(1)](https://invisible-island.net/ncurses/man/tic.1m.html)、[infocmp(1)](https://invisible-island.net/ncurses/man/infocmp.1m.html)、[toe(1)](https://invisible-island.net/ncurses/man/toe.1m.html)
- [term(5)：编译后 terminfo 文件格式，含传统格式与扩展数值格式](https://invisible-island.net/ncurses/man/term.5.html)
- [ncurses(3X)：TERMINFO、TERMINFO_DIRS、~/.terminfo 查找规则](https://invisible-island.net/ncurses/man/ncurses.3x.html)
- [terminfo.src 更新记录](https://invisible-island.net/ncurses/terminfo.src.html)
