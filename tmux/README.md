# tmux 3.8 纯静态构建

使用 Alpine 3.22 + musl，生成 Linux x86_64、aarch64 两种架构的纯静态 tmux。
目标机器不需要安装 musl、libevent、ncurses 或 utf8proc 共享库。

## 构建

需要 Docker 和默认 buildx；跨架构构建还需要宿主机已有可用的 binfmt/QEMU。
脚本只使用 `default` builder，不创建或修改 builder，也不自动安装模拟器。
构建阶段需要联网获取 Alpine 软件包和源码；产物运行不需要联网。

```sh
# 默认依次构建两个架构
./build.sh

# 单独构建，也接受 linux/amd64、linux/arm64 等名称
./build.sh amd64
./build.sh aarch64
```

产物分别保存，不会因切换架构互相覆盖：

```text
dist/
├── x86_64/tmux
└── aarch64/tmux
```

其他 Docker 构建参数放在架构参数之后：

```sh
./build.sh all --progress plain
./build.sh amd64 --build-arg ALPINE_VERSION=3.22
```

tmux 和 ncurses 源码固定版本并检查 SHA-256。升级时必须同时修改版本与匹配的哈希：

```sh
./build.sh all \
  --build-arg TMUX_VERSION=3.8 \
  --build-arg TMUX_SHA256=e79c699c7e949dccd0a4a125e17b8d1261e311b16979dbc8eb34542f3966d82e
```

Alpine 软件包使用该发行分支的仓库更新，并非所有传递依赖都锁定到不可变版本。

## 离线使用

复制与目标架构对应的 `tmux` 文件即可，不需要复制整个构建目录：

```sh
chmod +x ./tmux
./tmux -V
./tmux new-session -s work
```

常用操作：

- `Ctrl+b`，再按 `d`：退出客户端，后台保留会话。
- `./tmux attach-session -t work`：重新连接会话。
- `./tmux list-sessions`：查看会话。
- `Ctrl+b`，再按 `%` 或 `"`：左右或上下分屏。

tmux 3.8 默认启用鼠标；不需要时，在 `~/.tmux.conf` 中设置 `set -g mouse off`。
升级已有 tmux 时，先妥善结束旧版本会话并完全重启服务端；不要直接终止仍有任务的会话。
需要并行试用时可用 `./tmux -L static38 new-session -s work` 创建独立服务端。

## 功能取舍

- 静态链接 musl、libevent、宽字符 ncurses、utf8proc。
- 显式启用 SIXEL 图片支持、utf8proc Unicode 字符宽度处理。
- 保留 tmux 本身的会话、分屏、浮动窗格、鼠标、真彩色、剪贴板和控制模式等能力；
  具体显示效果仍取决于终端支持和配置。
- 不启用 systemd/cgroups 集成，避免依赖 systemd 服务与库。
- 不启用 utempter，避免依赖外置特权辅助程序；因此不提供该方式的 utmp 更新。
- 使用 musl 默认内存分配器，不额外引入 jemalloc。

## terminfo 与终端兼容性

静态链接不等于不需要终端定义。这里从源码构建 ncurses 6.5，并内嵌以下 fallback：

```text
ansi linux vt100 vt102 vt220
xterm xterm-256color xterm-direct
screen screen-256color tmux tmux-256color
rxvt rxvt-256color
alacritty alacritty-direct foot foot-direct xterm-kitty
```

tmux 优先读取目标机的 terminfo；找不到对应定义时再使用内嵌版本。
为 ncurses 的 `kitty` 条目补充了 `xterm-kitty` 别名；`rxvt-unicode` 不在该源码数据库中，
如需使用请另行提供它的 terminfo，不用普通 rxvt 条目冒充。
其他终端可通过目标机 terminfo 或 `TERMINFO` / `TERMINFO_DIRS` 提供定义。
也可通过 `--build-arg FALLBACK_TERMS=...` 修改内嵌列表（逗号分隔，需是 ncurses 源码已有条目）。

窗格内部默认 `TERM=screen-256color`，以兼容较老机器上的其他终端程序。
若目标机已安装 `tmux-256color` 定义，可在 `~/.tmux.conf` 设置：

```tmux
set -g default-terminal tmux-256color
```

**内嵌 terminfo 只供这个 tmux 使用**，不会为窗格里的 vim、less 等程序安装终端定义。
不要仅为消除报错就把任意终端的 `TERM` 改成不匹配的类型。

## 验证

每个架构导出前，Dockerfile 都会执行：

1. `file` 和 `readelf` 检查，确保 ELF 没有动态解释器及 `NEEDED` 共享库依赖。
2. `tmux -V` 版本检查。
3. 删除**构建容器内部**的 terminfo 数据库，运行 `smoke-test.py`，在真实 PTY 中验证
   xterm-256color、screen-256color、tmux-256color、linux、xterm-kitty、foot、alacritty
   的连接、分屏、Unicode 输出、断开及会话保留。

测试使用独立 socket 和空配置，不连接宿主机已有 tmux 服务端。
跨架构测试通过模拟器执行，不能替代真实 aarch64 机器的使用验证。

目标机器仍需 Linux PTY（通常为 `/dev/pts`）、可写 socket/临时目录、可执行 shell 和正确的用户信息。
推荐 UTF-8 locale，例如 `LANG=C.UTF-8`。tmux 配置调用的脚本、插件、剪贴板工具及窗格里的程序
仍需另行提供，不包含在这个二进制中。

## Reference Documentation

- [tmux 3.8 发布页](https://github.com/tmux/tmux/releases/tag/3.8)
- [官方 README](https://github.com/tmux/tmux/blob/3.8/README)
- [编译选项](https://github.com/tmux/tmux/blob/3.8/configure.ac)
- [3.8 发布讨论与升级注意事项](https://github.com/tmux/tmux/issues/5584)
- [ncurses 源码](https://invisible-mirror.net/archives/ncurses/)，其中 `INSTALL` 的
  `CONFIGURING FALLBACK ENTRIES` 说明内嵌终端定义的机制。
