# Neovim 0.12.6 静态离线版

采用官方 `STATIC_BUILD=ON` 路线，Alpine 3.22 + musl，目标为 Linux
x86_64 和 aarch64。二进制静态链接，但**需要随附的完整 runtime**。
不需要目标系统安装 glibc/musl 共享库、LuaJIT、libuv 或 terminfo。

## 构建与交付

在本目录执行，需要 Docker、默认 buildx；跨架构需要已有可用的 binfmt/QEMU。
脚本不创建 builder，不安装模拟器，不修改宿主系统。

```sh
sh ./build.sh           # 两种架构
sh ./build.sh amd64
sh ./build.sh aarch64
sh ./build.sh all --progress plain --build-arg BUILD_JOBS=4
```

有原生 ARM 主机时，优先在 ARM 主机直接构建，避免模拟器开销。共享目录环境可从当前机器执行：

```sh
ssh root@192.168.182.150 \
  'cd /root/workspace/mystatictools/neovim && sh ./build.sh aarch64 --progress plain'
```

共享的 `dist/aarch64` 不要同时被另一台机器的构建写入。

产物：

```text
dist/nvim-linux-x86_64.tar.gz
dist/nvim-linux-aarch64.tar.gz
dist/nvim-sources-x86_64.tar.gz   # 对应源码、依赖归档和构建适配，运行时不需要
dist/nvim-sources-aarch64.tar.gz
dist/x86_64/nvim/bin/nvim
dist/x86_64/nvim/share/nvim/runtime/
dist/aarch64/nvim/bin/nvim
dist/aarch64/nvim/share/nvim/runtime/
```

源码版本和 SHA-256 固定在 Dockerfile；依赖版本和 SHA-256 采用该版源码
`cmake.deps/deps.txt`，`fetch-deps.py` 下载时重试并校验，CMake 再次校验。
Alpine 构建工具随 3.22 仓库更新，并非所有构建工具都锁定到不可变版本。
新增工具/插件的版本、下载地址与 SHA-256 固定在 `extras.json`，升级必须同步更新哈希。

## 离线使用

将对应架构的压缩包完整复制到目标机，解压到任意可写目录：

```sh
tar -xzf nvim-linux-x86_64.tar.gz
./nvim/bin/nvim --version
./nvim/bin/nvim your-file.conf
# 可选离线配置，先试用，不覆盖已有配置
./nvim/bin/nvim -u ./nvim/examples/init.lua your-file.conf
```

### 内置 nvim-tree 文件树

随包提供 **nvim-tree v1.19.0**，版本标签 `nvim-tree-v1.19.0`，源码和 SHA-256
固定在 Dockerfile。插件为纯 Lua，不需要 `.so`、插件管理器或联网安装。

使用上面的 `-u ./nvim/examples/init.lua` 启用。普通模式按 **`\e`** 开关侧边栏；
在树中按 `Enter` 打开文件，`a` 新建，`r` 重命名，`c` 复制、`p` 粘贴，`d` 删除，
`g?` 查看帮助。删除保留确认提示；不附带回收站工具，谨慎操作。

示例配置禁用 netrw，由 nvim-tree 接管本地目录浏览；因此该配置不提供 netrw 的
`scp://` / `sftp://` 远程文件功能。Git 和诊断集成、特殊字体图标均关闭，
无需额外的 git、语言服务器、nvim-web-devicons 或 Nerd Font。

插件放在随包 runtime 的原生可选包目录：

```text
nvim/share/nvim/runtime/pack/offline/opt/nvim-tree.lua/
```

示例通过 `packadd nvim-tree.lua` 加载后执行 `setup()`，移动整个安装目录后仍有效。
它不会自动修改用户配置；只运行 `bin/nvim` 或 `-u NONE` 不会主动启用该插件。
已有自己的 `init.lua` 时，可参考 `examples/init.lua` 合并 nvim-tree 配置。

### 高亮、缩进线、格式化和对齐

使用随包示例配置时，启用 Neovim 内置 **habamax** 配色，以及 Nginx、Shell、JSON、
YAML、XML、Python、Java properties 的内置文件类型和传统语法高亮。
无对应 Tree-sitter 解析器的语言不会尝试下载或加载 `.so`。

随附 `indent-blankline.nvim 3.10.1` 显示缩进参考线（`│`），关闭需要 Tree-sitter
的作用域功能；无需 Nerd Font。线条只是显示辅助，不改变实际空白。

普通模式按 **`\f`** 或执行 `:OfflineFormat`，手动处理当前文件：

| 文件 | 随包工具 | 默认行为 |
| --- | --- | --- |
| Shell | shfmt 3.14.1 | 两空格缩进；语法错误时保留原文 |
| JSON | jq 1.8.2 | 两空格排版，不主动排序；不支持 JSONC 注释 |
| YAML | yamlfmt 0.21.0 | 两空格缩进，可能调整布局，需检查差异 |
| Python | Ruff 0.17.1 | `ruff format`，无需 Python；不执行 lint 自动修复 |
| XML | xmllint / libxml2 2.15.4 | 两空格排版，不加载网络 DTD、不展开外部实体 |
| Nginx | Neovim 内置 indent | 只重新缩进，不能替代 `nginx -t` |
| properties | 不自动格式化 | 保留编码、转义、顺序和续行；只提示手动对齐 |

格式化由 `conform.nvim 9.1.0` 接入，**不设置保存时格式化，不自动写文件**。
工具失败不把部分输出覆盖到缓冲区，可用 `u` 撤销成功的格式化。
XML 混合内容的空白可能有意义；JSON 重复键经过 jq 可能被合并、数值也需注意精度，
重要配置应检查 diff/备份，不把“解析成功”当作“配置语义没有变化”。

工具位于 `nvim/libexec/`，配置相对当前 nvim 的实际位置定位，不依赖系统 PATH，
移动整个目录仍有效。shfmt、yamlfmt 使用上游官方 Go 发布二进制，Ruff 使用上游官方
musl 发布二进制；均校验 SHA-256、ELF 架构及静态依赖。jq 和 xmllint 在 Alpine/musl
内从固定源码构建。xmllint 保留常规解析、编码转换、DTD/schema 等能力；只关闭静态程序
无法使用的动态模块加载功能，不附带 Python binding 或交互 shell 的 readline。
各工具匹配源码、上游原始发布文件和顶层许可证一并保存于源码包。

`mini.align 0.18.0` 用于手动列对齐：选中简单键值行，按 `gA` 开始预览，按 `s`，
输入 `=` 后回车设置分隔符，再按回车接受；按 Esc 取消。可用 `t` 修整列边缘空白。
这不是 Java properties 解析器，不要对转义键、带续行或特殊空白的配置批量对齐。
不强制转换 properties 编码，ISO-8859-1/UTF-8 取决于实际应用的加载方式。

`bin/nvim` 相对定位 `../share/nvim/runtime`；不要单独移动二进制。
若机器已有其他 Vim/Neovim，确认没有遗留的 `VIM` / `VIMRUNTIME` 指向旧版本。
推荐 `LANG=C.UTF-8`。本包不自动更改 PATH、不覆盖 `~/.config/nvim`。

保留文件编辑、撤销/重做、搜索替换、分屏、标签、宏、正则、UTF-8、传统语法高亮、
文件类型/缩进、帮助文档、netrw，以及 LuaJIT、LPeg、Vimscript、作业/终端、RPC、LSP 客户端代码。
不附带语言服务器，也不自动下载插件；未通过编译选项硬删 LSP。

## 插件支持与静态边界

支持离线复制的纯 Vimscript、纯 Lua 插件。推荐直接使用原生 package 目录：

```text
~/.local/share/nvim/site/pack/offline/start/插件名/plugin/...
~/.local/share/nvim/site/pack/offline/start/插件名/lua/...
~/.local/share/nvim/site/pack/offline/opt/按需插件/...
```

`start` 自动加载；`opt` 使用 `:packadd 插件名`。插件需要的所有依赖也要提前复制，
不要在纯内网配置中保留插件管理器的自动安装/更新、首次启动下载逻辑。

**静态 musl 不支持 `dlopen()` 加载 `.so`。** 因此：

- 支持内置 LuaJIT、LPeg、luv；其他需要动态 Lua C 模块、FFI 加载外部共享库的插件不保证可用。
- 默认的官方 Tree-sitter 解析器 C、Lua、Vim、Vimdoc、Query、Markdown、Markdown inline
  通过本仓库 `static-parsers.py` 静态内嵌；Lua/Markdown/帮助文档不会因加载 `.so` 而失效。
- 这是对官方源码的本地适配：依赖构建改为静态 archive，主程序链接 archive，
  解析器加载器为这 7 种语言显式选择内嵌实现。没有伪造 `.so` 或终端别名。
- 不支持直接添加第三方 Tree-sitter `.so`；若需更多语言的 Tree-sitter，需要扩展静态构建并重新验证。
  其他语言仍可使用随附的传统 syntax/indent。
- Python/Node/Ruby/Perl provider、git、rg、fd、diff、shell 等不是静态二进制的一部分。
  仅上述五种格式化工具随目录分发，并未编译进 nvim ELF；其他外部程序仍需另行提供。
  依赖它们的插件需另行部署；netrw 的远程/压缩文件操作也可能调用外部命令。
- 内置 `:terminal` 和 job 功能要求目标机有可执行 shell/命令、Linux PTY（`/dev/pts`），
  不代表附带一个 shell。RPC socket、配置/状态、交换/撤销文件也需要目录权限。
- 不启用 Wasmtime；沿用官方默认关闭的翻译构建选项，保留英文帮助及错误消息。

## 与 tmux 配合

Neovim 自带终端 fallback，保留 unibilium 对系统 terminfo 的正常查询。
没有系统 terminfo 时，也可识别 `screen-256color` 和 `tmux-256color`，无需把 TERM 硬改为 xterm。
与本仓库 `tmux/` 静态版本一起使用时，两者各自处理终端定义，不共享内嵌数据库。

建议的 `~/.tmux.conf`（按需手动合并）：

```tmux
set -g default-terminal tmux-256color
# 可选：tmux 鼠标会接管终端选择；想使用终端原生鼠标时不启用
# set -g mouse on
set -s escape-time 10
# 仅当外层终端确实支持 RGB 时启用；按实际客户端 TERM 调整匹配范围
set -as terminal-features ',xterm*:RGB'
```

如果同一 tmux 会话中其他程序依赖系统 terminfo，而目标机没有 tmux-256color 定义，
可保留仓库 tmux 的默认 screen-256color。不要对任意终端伪造 TERM。
修改已有服务端配置不会自动替换已有窗格的环境；建议新建独立测试服务端：

```sh
tmux -L nvim-offline -f ./your-test-tmux.conf new-session
```

示例 Neovim 配置启用真彩色，默认关闭编辑器鼠标，把选择/右键交给终端。
按 `\m` 可临时开关编辑器鼠标；开启后可用鼠标操作文件树、光标和编辑器分屏。
tmux 前缀键仍由 tmux 接管；不强制重映射
`Ctrl+h/j/k/l`，避免破坏编辑和终端应用的原有操作。Neovim 终端模式用
`Ctrl+\\`、`Ctrl+n` 回普通模式。

### 复制粘贴：不再强制 OSC 52

示例已删除此前的 OSC 52 provider、`\y` 映射及 `+`/`*` 回退到内部寄存器的逻辑，
同时关闭示例中的 OSC 52 自动探测和 clipboard 同步。Neovim 内部使用 `y` / `p`；
跨 SSH 使用本地终端复制/粘贴（Mac 通常是 `Cmd+C` / `Cmd+V`），支持 bracketed paste。

Neovim 的 OSC 52 底层能力仍保留，测试也可显式调用；不是通过裁掉功能解决交互混淆。
若 tmux 开启了鼠标，即使 Neovim `mouse=`，鼠标仍可能被 tmux 接管；可按终端支持的
Shift+鼠标方式绕过，或在独立 tmux 配置中关闭鼠标。不要为此直接修改正在用的会话。

## 验证范围

Docker 导出前在断网的测试步骤中强制执行功能检查，失败不导出：

1. `file`、`readelf -l/-d`：无动态解释器、无 NEEDED；打印版本和 ELF 架构。
2. 完整目录移动后启动，不手工设置 VIMRUNTIME，检查帮助 runtime 的定位。
3. headless：中文读写、撤销、分屏、filetype/syntax、原生 package 中的 Lua/Vimscript
   插件、LPeg、七种内置解析器加载及 Lua 实际解析、子进程和 PTY terminal job。
4. 隐藏系统 terminfo 后，在真实 PTY 中分别使用 xterm-256color、screen-256color、
   tmux-256color、linux，验证直接启动及隔离 tmux 会话内的输入/保存/退出。
   测试 tmux 单独使用构建期数据库，不让 Neovim 读取该数据库。
5. 在 scratch 根文件系统中断网重复编辑、插件和解析器测试；该环境没有系统共享库、
   shell、解释器或 terminfo，因此不运行依赖外部 shell 的 job/terminal 子测试。
6. 使用随包示例配置，在隔离临时目录实际调用 nvim-tree 完成目录浏览、新建、打开编辑、
   重命名、复制、删除和关闭文件树；此测试也在 scratch 中执行，不借助外部文件管理命令。
7. 各格式实际输入输出、错误输入原文保留、XML 外部实体不展开、Nginx 重新缩进、properties
   原文保留和 mini.align 列对齐；在 scratch 中直接调用随包静态程序，不需要 shell。

构建与测试是否原生执行取决于执行主机：在 x86_64 主机上构建 arm64 使用模拟器，
在 aarch64 主机上构建 arm64 为原生执行；模拟器测试不能代替真实 ARM 机器测试。
自动测试不等于验证了所有实体终端：真彩色显示、鼠标手感、SSH/堡垒机链路、
桌面剪贴板落地和具体第三方插件仍需在实际客户端试用。

本轮交付的 aarch64 产物已在 `192.168.182.150`（原生 aarch64）重新构建，
上述 Docker 断网功能测试、无系统 terminfo 的 PTY/tmux 测试及 scratch 测试均已通过，
不只依赖模拟器测试结果。

## Reference Documentation

- [官方静态构建说明](https://neovim.io/doc/build/#build-static-binary-linux)
- [0.12.6 官方发布页](https://github.com/neovim/neovim/releases/tag/v0.12.6)
- [该版本构建说明](https://github.com/neovim/neovim/blob/v0.12.6/BUILD.md)
- [固定依赖和校验值](https://github.com/neovim/neovim/blob/v0.12.6/cmake.deps/deps.txt)
- [终端说明](https://neovim.io/doc/user/term.html)
- [剪贴板 provider 与 OSC 52](https://neovim.io/doc/user/provider.html#clipboard-osc52)
- [原生离线 packages](https://neovim.io/doc/user/pack.html)
- [nvim-tree 固定版本](https://github.com/nvim-tree/nvim-tree.lua/releases/tag/nvim-tree-v1.19.0)
- [nvim-tree 文档](https://github.com/nvim-tree/nvim-tree.lua/blob/nvim-tree-v1.19.0/doc/nvim-tree-lua.txt)
- [conform.nvim 文档](https://github.com/stevearc/conform.nvim/tree/v9.1.0)
- [缩进参考线](https://github.com/lukas-reineke/indent-blankline.nvim/tree/v3.10.1)
- [mini.align](https://github.com/nvim-mini/mini.align/tree/v0.18.0)
- [shfmt](https://github.com/mvdan/sh/releases/tag/v3.14.1)、[yamlfmt](https://github.com/google/yamlfmt/releases/tag/v0.21.0)
- [jq](https://github.com/jqlang/jq/releases/tag/jq-1.8.2)、[Ruff](https://github.com/astral-sh/ruff/releases/tag/0.17.1)
- [libxml2 源码](https://download.gnome.org/sources/libxml2/2.15/)、[xmllint 手册](https://gnome.pages.gitlab.gnome.org/libxml2/xmllint.html)

分发包保留 Neovim LICENSE 和依赖顶层许可文件；同时导出匹配版本的源码包，
包含原始 Neovim 源码、固定依赖归档及构建脚本。需要再分发时，请同时提供对应源码包，
遵守依赖许可（尤其静态链接的 unibilium LGPL 对修改、重新链接等权利的要求）。
