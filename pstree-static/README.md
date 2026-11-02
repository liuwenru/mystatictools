# pstree 23.7 纯静态版 + procs 0.14.12

- `pstree`：来自 psmisc 23.7（2024-03-03 发布，经 GitLab 标签和 SourceForge 下载页核实为当前最新版本），
  使用 Alpine 3.22 + musl 从源码静态构建，ncurses 6.6 和 GNU libintl 都静态链接。
- `procs`：dalance/procs 0.14.12（2026-06-25 发布，经 GitHub Releases 核实为当前最新版本）
  **官方发布的 Linux 二进制，未重新编译**。官方用 Rust musl 目标构建，本身就是纯静态
  （x86_64 为 static-pie，aarch64 为普通静态），构建时只下载、校验并测试。

支持 Linux x86_64 / aarch64，运行时不需要共享库或动态加载器。

## 构建和产物

需要 Docker、默认 buildx，构建需要联网。默认只构建当前主机架构：

```sh
./build.sh
./build.sh amd64 --progress plain
./build.sh aarch64 --progress plain
./build.sh all             # 仅在已有跨架构执行能力时使用
```

x86_64 在本机原生构建，aarch64 在 `192.168.182.150` 原生构建。
脚本不创建、修改或切换 builder，不安装模拟器。共享目录下不要在两台机器上并发构建同一架构。

```text
dist/
├── x86_64/       # pstree、pstree.1、COPYING.psmisc、procs、LICENSE.procs、SHA256SUMS
├── aarch64/
├── pstree-23.7-procs-0.14.12-linux-x86_64-static.tar.gz
└── pstree-23.7-procs-0.14.12-linux-aarch64-static.tar.gz
```

| 文件 | x86_64 | aarch64 | 说明 |
| --- | --- | --- | --- |
| `pstree` | 约 485 KB | 约 506 KB | 自建静态二进制 |
| `procs` | 约 6.5 MB | 约 5.9 MB | 官方二进制，与发布包内文件逐字节相同 |
| `pstree.1` | | | 官方手册页，`man ./pstree.1` |
| `COPYING.psmisc` / `LICENSE.procs` | | | GPL-2.0 / MIT |

### 固定版本与校验

| 组件 | 来源 | SHA-256 | 校验依据 |
| --- | --- | --- | --- |
| psmisc-23.7.tar.xz | SourceForge | `58c55d9c…c327` | 下载页公布的 SHA-1、MD5 一致 |
| ncurses-6.6.tar.gz | invisible-mirror.net | `355b4cbb…ff11` | 作者 GPG 签名验证通过 |
| procs x86_64 zip | GitHub Releases | `81964faf…1713` | 与 GitHub 资产 digest 一致 |
| procs aarch64 zip | GitHub Releases | `74b4f82a…9f91` | 与 GitHub 资产 digest 一致 |
| procs LICENSE | v0.14.12 标签 | `feb87a2e…510d` | 首次下载计算 |

完整哈希见 Dockerfile。Alpine 依赖随 3.22 分支仓库更新，未锁定版本，本次实际使用：
gcc 14.2.0、musl 1.2.5、gettext-static 0.24.1。
升级时同步修改 Dockerfile 中的版本和哈希、`build.sh` 中的版本、`test/smoke-test.py` 中的版本断言。

## pstree 编译取舍

只构建 psmisc 中的 `pstree`；`killall`、`fuser`、`peekfd`、`prtstat` 不在本次范围内，需要时可另加。

- **ncurses 6.6 自建**：pstree 的 `-h`/`-H` 高亮要查 terminfo。构建方式与本仓库 tmux 相同，
  内嵌以下终端定义，目标机有 terminfo 时优先使用目标机的：

  ```text
  ansi linux vt100 vt102 vt220 xterm xterm-256color xterm-direct
  screen screen-256color tmux tmux-256color rxvt rxvt-256color
  alacritty alacritty-direct foot foot-direct xterm-kitty
  ```

  pstree 只用 termcap 层接口，因此构建窄字符的独立 `libtinfo`（`--with-termlib --disable-widec`）。
  configure 会因构建容器 `/etc/passwd` 中没有普通用户而禁止 root 使用 `TERMINFO`、`TERMINFO_DIRS`、
  `~/.terminfo`，这里设置 `cf_cv_multiuser=yes`，与发行版 ncurses 一致。
- **启用 NLS（静态 GNU libintl）**：pstree 只有在启用 NLS 时才调用 `setlocale`，
  关掉后即使 `LANG=zh_CN.UTF-8` 也只会输出 ASCII 线条。翻译目录为 `/usr/share/locale`，
  与发行版 psmisc 的 `.mo` 位置相同：目标机装了 psmisc 翻译就显示中文帮助和报错，
  没有就显示英文，不影响功能。运行包不带 `.mo`。
- **SELinux/AppArmor 库不启用**：pstree 是用 `dlopen` 加载 libselinux/libapparmor 的，
  静态程序做不到。不启用时 `-Z` 走上游的后备逻辑，直接读 `/proc/PID/attr/current`，
  在 SELinux 或 AppArmor 系统上都能显示上下文。
- 未安装 `pstree.x11` 链接（仅用于 X11 下运行完后等待按键）。
- 保留上游默认的加固编译参数（`-fstack-protector-strong`、`-Wl,-z,relro` 等）。

## 使用

```sh
./pstree                     # 从 PID 1 开始
./pstree -p -a 1234          # 显示 PID 和命令参数
./pstree -u -s 1234          # 显示 UID 变化和父进程链
./pstree -t -c -p nginx      # 显示线程实际名称、不合并；参数 nginx 是用户名
./pstree -H 1234             # 高亮指定进程及其祖先，需要 TERM
./pstree -S -N net           # 命名空间

./procs                       # 进程列表
./procs nginx                 # 按命令行、PID、用户搜索
./procs --or 1234 5678        # 多个关键字默认 AND，需要 OR 时加 --or
./procs --tree --thread 1234
./procs --watch               # 类似 top，按 q 退出
./procs --json --pager disable > ps.json
./procs --gen-config > ~/.config/procs/config.toml
```

## 运行依赖与行为

两个程序都只读取 `/proc`，需要挂载 procfs；看其他用户进程的完整信息需要相应权限（通常是 root）。

pstree：

- **线条**：输出到终端时，locale 为 UTF-8 用 UTF-8 线条，否则用 ASCII；输出到管道总是 ASCII。
  musl 没有设置 `LANG`/`LC_*` 时默认就是 C.UTF-8，因此默认就是 UTF-8 线条。
  `-A`/`-U`/`-G` 可强制选择。
- **用户名**：`-u` 和按用户名查询只读 `/etc/passwd`，不走 NSS，LDAP/SSSD 用户显示为数字 UID。
- **`-h`/`-H` 高亮**：需要 `TERM`；目标机 terminfo 和上面的内嵌定义都没有该终端时，
  `-H` 报 `Can't get terminal capabilities`。`-C age` 颜色是写死的 ANSI 序列，不需要 terminfo。
- **`-Z`**：内核没有启用 LSM 时显示空的 `` (`') ``。

procs：

- **终端主题探测**：输出到终端且 `theme` 为 auto 时，procs 会向终端发查询并**一直等待应答**。
  普通终端模拟器正常；串口控制台、部分 Web 控制台不应答时 procs 会卡住不动。
  这种情况用 `--theme dark`（或 `light`），或在配置文件写 `[display] theme = "Dark"`。
  输出到管道时不探测。
- **分页器**：输出超过一屏时调用 `less -SR`，没有则用 `more -f`；两者都没有时直接输出（已验证）。
  也可在配置中用 `use_builtin = true` 使用内置分页器，或 `--pager disable`。
- **配置文件**：可选，`~/.config/procs/config.toml` 或 `~/.procs.toml`，没有就用默认配置。
- **Docker 列**：能访问 `/var/run/docker.sock` 时才显示容器名。
- **用户名**：读 `/etc/passwd`，同样不走 NSS。
- 不需要 terminfo，颜色是 ANSI 序列。

## 已知行为（不是静态编译造成的）

- pstree 默认把线程显示为 `{父进程名}`，要看线程自己的名字加 `-t`。
- procs 按命令行搜索，不按内核 comm 名称：进程用 prctl 等方式改过 comm 时，用新名字搜不到（pstree 显示的是 comm）。
- procs 的多个关键字默认是 AND 关系。

## 验证

构建阶段必须通过下列检查才导出：

1. pstree、procs 的 `file`、`readelf -h` 架构；`readelf -l` 无 `INTERP`，`readelf -d` 无 `NEEDED`。
2. 版本分别为 23.7、0.14.12；configure 确认使用 `-ltinfo`、`-lintl`、NLS 启用、localedir 正确。
3. 删除构建容器中全部 terminfo 数据库后运行 `test/smoke-test.py`，用固定进程树
   （改名的父进程、root/nobody/4321 子进程、2 个命名线程）测试：
   - pstree：合并/`-c`/`-t`/`-T`、`-p -n -a -u -g -s`、`-U -G -A`、`-C age`、`-Z`、`-S`、`-N`、
     用户名参数、`COLUMNS` 截断与 `-l`；伪终端中默认/`zh_CN.UTF-8` 为 UTF-8 线条、`LC_ALL=C` 为 ASCII；
     中文翻译；6 种内嵌终端的 `-H` 高亮；未知终端和无 `TERM` 报错；`TERMINFO` 指向自编译条目时优先使用。
   - procs：文本/正则搜索、`--json` 及用户名、`--tree` 含线程、`--thread`、`--sortd --only`、
     `--gen-config`、bash 补全、伪终端中无 less/more 直接输出、`--watch` 按 q 退出。

上游 psmisc 测试套件没有 pstree 用例，未运行。测试主机和结果见 `test/VALIDATION.md`。

## Reference Documentation

- [psmisc GitLab（官方）](https://gitlab.com/psmisc/psmisc)
- [psmisc 下载页（SourceForge）](https://sourceforge.net/projects/psmisc/files/psmisc/)
- [psmisc 23.7 ChangeLog](https://gitlab.com/psmisc/psmisc/-/blob/v23.7/ChangeLog)
- [pstree 手册页](https://gitlab.com/psmisc/psmisc/-/blob/v23.7/doc/pstree.1)
- [ncurses 官方主页](https://invisible-island.net/ncurses/)
- [ncurses 安装说明（fallback、root-environ 等 configure 选项）](https://invisible-island.net/ncurses/INSTALL.html)
- [procs GitHub（官方）](https://github.com/dalance/procs)
- [procs 0.14.12 发布页](https://github.com/dalance/procs/releases/tag/v0.14.12)
- [procs 配置说明](https://github.com/dalance/procs#configuration)
