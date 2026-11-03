# Neovim 0.12.6 静态离线版

采用官方 `STATIC_BUILD=ON` 路线，Alpine 3.22 + musl，目标为 Linux
x86_64 和 aarch64。二进制静态链接，但**需要随附的完整 runtime**。
不需要目标系统安装 glibc/musl 共享库、LuaJIT、libuv 或 terminfo。

## 构建与交付

### 目录结构

```text
build.sh              # 构建打包入口
pushfdoc.sh           # 发布入口
Dockerfile            # 静态构建、离线测试和产物导出
init-offline.lua      # 随运行包交付的示例配置，安装为 nvim/examples/init.lua
doc/offline.txt        # 中文离线帮助，安装到 runtime/doc，支持 :OfflineHelp 和 :help offline
biome-jsonc.json      # 随包 JSONC 格式化配置，安装为 nvim/libexec/biome-jsonc.json
completion/           # 九类词库、手工补录、官方资料快照和离线 Lua 补全
generate-completion.py # 从固定快照提取关键字；仅维护/构建时需要 Python
extras.json           # 附加工具与插件的版本和校验值
fetch-deps.py         # 下载 Neovim 构建依赖
fetch-extras.py       # 下载附加工具与插件
lsp-node/             # Node 语言服务器的 package.json 和 package-lock.json（固定版本和 integrity）
static-parsers.py     # 静态解析器构建适配
bundle-sources.py     # 收集源码和许可证
test/                 # headless、PTY/tmux、文件树、增强功能及随包 LSP 测试
dist/                 # 分架构产物、运行包和源码包
```

测试脚本在构建容器中位于 `/build/test/`，scratch 测试中位于 `/tests/`；
`/test/` 仅存放 scratch 测试运行时生成的临时状态。
源码包保留 `sources/build/test/` 目录，与仓库布局一致，便于解压后重新构建。
测试脚本不随最终运行包交付；`init-offline.lua` 保留在项目外层。

### 执行构建

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

使用随包示例配置时，启用随包内置的 **OneDark 1.0.3** 配色（`navarasu/onedark.nvim`，
`dark` 风格），以及 Nginx、Shell、JSON、
YAML、XML、Python、Java properties 的内置文件类型和传统语法高亮。
无对应 Tree-sitter 解析器的语言不会尝试下载或加载 `.so`。

主题是纯 Lua，放在 `nvim/share/nvim/runtime/pack/offline/opt/onedark.nvim/`，
无需联网、插件管理器或动态库；版本与 SHA-256 固定在 `extras.json`，源码和许可证随包保留。
它随 runtime 分发，不是编译进 Neovim ELF；不会自动覆盖个人配置。
已有自己的配置时，在 `init.lua` 中加入：

```lua
vim.opt.termguicolors = true
vim.cmd('packadd onedark.nvim')
require('onedark').setup({style = 'dark'})
require('onedark').load()
```

可将 `style` 改为 `darker`、`cool`、`deep`、`warm`、`warmer` 或 `light`。
临时回到原配色可执行 `:colorscheme habamax`；恢复执行 `:colorscheme onedark`。
真彩色效果取决于实际终端及 tmux/SSH 链路，主题本身不要求 Nerd Font 或 Tree-sitter。

#### 终端颜色模式：普通模式按 `\c` 轮换

随包示例配置默认使用真彩色，按 **`\c`** 依次切换以下三档，并提示当前模式：

| 模式 | 主题 | 缩进参考线 |
| --- | --- | --- |
| `truecolor` | OneDark dark，启用 RGB | 接近背景的淡灰色细线 |
| `256` | 内置 habamax，关闭 RGB | 接近背景的灰色细线 |
| `ansi` | 内置 vim，关闭 RGB，基础 16 色 | 关闭，避免少色环境下干扰正文 |

也可执行 `:OfflineColor ansi`、`:OfflineColor 256`、`:OfflineColor truecolor`；
不带参数的 `:OfflineColor` 与 `\c` 相同。若个人设置了 mapleader，快捷键随之变化。
切换后记住所选模式，下次启动沿用，不必每次重新按 `\c`。记录写在 Neovim state 目录的
`offline-color`（通常为 `~/.local/state/nvim/offline-color`，只有一行模式名），不改个人配置、
文件内容和 `TERM`；`-i NONE` 只关闭 ShaDa，不影响此记录。
启动时优先级：`NVIM_OFFLINE_COLOR` > 记录 > `truecolor`。恢复默认执行 `:OfflineColor truecolor`
或删除该文件；记录内容无效时提示并按 truecolor 启动。HOME 只读等无法写入时，本次切换照常生效，
提示未能保存。多台终端共用同一用户时记录是共享的，低色终端可临时用环境变量覆盖。

临时指定启动模式（不写入记录），适合偶尔从低色终端登录：

```sh
NVIM_OFFLINE_COLOR=ansi ./nvim/bin/nvim -u ./nvim/examples/init.lua your-file.conf
NVIM_OFFLINE_COLOR=256 ./nvim/bin/nvim -u ./nvim/examples/init.lua your-file.conf
```

ANSI 模式保留终端默认正文前景/背景，实际色值取决于终端调色板；不能还原 OneDark。
这些模式调整 Neovim 显示方式，不会让终端获得原本不支持的颜色能力；256 色模式也需要
实际终端及链路支持。无需新增主题插件，文件树、搜索和语法高亮沿用所选主题。

#### 光标颜色与当前行/列底色

示例配置开启 `cursorline`，用主题自带的淡色底色标出光标所在行。
`cursorcolumn`（当前列底色）**默认关闭**，普通模式按 **`\l`** 临时开关，适合对齐 YAML/XML 缩进时使用。
关闭原因：当前列底色要求光标每移动一格都重画整个窗口，并对每行重跑传统正则语法高亮。
本机 3000 行 Nginx 配置、200×50 终端实测，每次移动开启时约 2.5 ms，关闭后约 0.1 ms；
走 SSH/tmux 时每步还要重发整屏内容，体感卡顿更明显。补全词库只在插入模式输入时按需加载，
与光标移动卡顿无关。
普通/插入模式光标为红色（`#ff3b30`，插入模式为竖线）；**可视模式改为红色下划线**，
因为块状光标会盖住选区末尾那个字符的选区底色。OneDark 原本的 `Visual`（`#3b3f4c`）
和当前行/列底色（`#31353f`）几乎分不出来，这里加深为蓝灰 `#3e5175`；256（habamax 反色）
和 ANSI（浅灰底）的选区本来就与当前行/列区分明显，不改。

- 光标颜色通过终端 OSC 12 设置，退出时 Neovim 发送 OSC 112 恢复终端原光标颜色。
  **Neovim 只在 truecolor 模式下发送光标颜色**；256/ANSI 模式仍是终端自己的光标颜色，
  光标形状（块/竖线/下划线）照常切换。
- 终端或 tmux 不支持 OSC 12 时，光标保持终端原有颜色，不影响编辑；tmux 下未实测。
- 当前行底色开销很小；也不需要时执行 `:set nocursorline`。

随附 `indent-blankline.nvim 3.10.1` 显示缩进参考线（`│`），关闭需要 Tree-sitter
的作用域功能；无需 Nerd Font。真彩色/256 色使用独立淡色高亮，不再借用正文或注释颜色，
ANSI 模式关闭。线条只是显示辅助，不改变实际空白。

普通模式按 **`\f`** 或执行 `:OfflineFormat`，手动处理当前文件：

| 文件 | 随包工具 | 默认行为 |
| --- | --- | --- |
| Shell | shfmt 3.14.1 | 两空格缩进；语法错误时保留原文 |
| JSON | jq 1.8.2 | 两空格排版，不主动排序；不支持 JSONC 注释 |
| JSONC | Biome 2.6.2 | 两空格缩进，保留注释和键顺序；接受并去掉尾逗号，不执行 lint/assist |
| YAML | yamlfmt 0.21.0 | 两空格缩进，可能调整布局，需检查差异 |
| Python | Ruff 0.17.1 | `ruff format`，无需 Python；不执行 lint 自动修复 |
| XML | xmllint / libxml2 2.15.4 | 两空格排版，不加载网络 DTD、不展开外部实体 |
| Nginx | nginxfmt.py 1.3.0 | 两空格缩进，需要系统 `python3`；不能替代 `nginx -t` |
| properties | 不自动格式化 | 保留编码、转义、顺序和续行；只提示手动对齐 |

格式化由 `conform.nvim 9.1.0` 接入，**不设置保存时格式化，不自动写文件**。
工具失败不把部分输出覆盖到缓冲区，可用 `u` 撤销成功的格式化。
XML 混合内容的空白可能有意义；JSON 重复键经过 jq 可能被合并、数值也需注意精度，
重要配置应检查 diff/备份，不把“解析成功”当作“配置语义没有变化”。

工具位于 `nvim/libexec/`，配置相对当前 nvim 的实际位置定位，不依赖系统 PATH，
移动整个目录仍有效。例外是 Nginx 格式化：随包脚本由 PATH 中的系统 `python3` 执行，
不附带 Python 解释器；缺少时明确提示并保留正文，不退回内置重新缩进。
脚本使用标准库，通过管道处理缓冲区，不直接写原文件。脚本与 SHA-256 固定在
`extras.json`，原始脚本（含 Apache 2.0 许可声明）保留于源码包。
它不是完整 Nginx 语法校验器；复杂引号、转义、正则、行尾注释和嵌入脚本可能受影响，
成功退出不代表配置语义不变，应检查差异并另用 `nginx -t`。
shfmt、yamlfmt 使用上游官方 Go 发布二进制，Ruff 使用上游官方
musl 发布二进制；Biome 使用官方双架构 musl 静态程序，同样校验 SHA-256、ELF 架构及静态依赖。
jq 和 xmllint 在 Alpine/musl
内从固定源码构建。xmllint 保留常规解析、编码转换、DTD/schema 等能力；只关闭静态程序
无法使用的动态模块加载功能，不附带 Python binding 或交互 shell 的 readline。
各工具匹配源码、上游原始发布文件和顶层许可证一并保存于源码包。

**JSONC**：`.jsonc` 文件自动识别，普通模式按 `\f` 格式化，无需 Node.js、Python 或 LSP。
带注释但名为 `.json` / `.conf` 的文件，可先执行 `:set filetype=jsonc`；不会自动将所有 JSON
当作 JSONC。普通 JSON 仍使用 jq。

Biome 只运行 `format`，通过 stdin/stdout 处理正文，不使用 `--write`、lint、assist 或常驻服务。
固定使用随包的 `libexec/biome-jsonc.json` 和虚拟 `.jsonc` 文件名，避免读取项目中的
`biome.json` / `biome.jsonc` / `.editorconfig`。不排序、不主动合并重复键，测试覆盖大整数文本保留；
但不代替配置语义检查。输入有语法错误时不覆盖正文；注释内容保留，排版和位置可能调整。
stdin 模式不能依赖 Biome 文件扫描的默认大小限制；大文件仍会占用内存，沿用 10 秒格式化超时。
Biome 版本、源码及双架构二进制哈希固定在 `extras.json`，许可证为 MIT / Apache-2.0，随包保留。

`mini.align 0.18.0` 用于手动列对齐：选中简单键值行，按 `gA` 开始预览，按 `s`，
输入 `=` 后回车设置分隔符，再按回车接受；按 Esc 取消。可用 `t` 修整列边缘空白。
这不是 Java properties 解析器，不要对转义键、带续行或特殊空白的配置批量对齐。
不强制转换 properties 编码，ISO-8859-1/UTF-8 取决于实际应用的加载方式。

`bin/nvim` 相对定位 `../share/nvim/runtime`；不要单独移动二进制。
若机器已有其他 Vim/Neovim，确认没有遗留的 `VIM` / `VIMRUNTIME` 指向旧版本。
推荐 `LANG=C.UTF-8`。本包不自动更改 PATH、不覆盖 `~/.config/nvim`。

保留文件编辑、撤销/重做、搜索替换、分屏、标签、宏、正则、UTF-8、传统语法高亮、
文件类型/缩进、帮助文档、netrw，以及 LuaJIT、LPeg、Vimscript、作业/终端、RPC、LSP 客户端代码。
随包附带 Python、JS/TS、YAML、JSON、Shell 的语言服务器（见“随包语言服务器”），不自动下载插件或服务器；未通过编译选项硬删 LSP。

### 离线帮助与补全总开关

加载示例配置后可在 Neovim 中查询，不需要联网或 Shell：

```vim
:OfflineHelp                 " 总览和常用操作
:OfflineHelp current         " 按当前文件推荐章节
:OfflineHelp completion      " 所有补全开关、词库选择及手工补录
:OfflineHelp headers         " HTTP Header 补全
:OfflineHelp nginx           " Nginx 补全及格式化
:OfflineHelp format          " 格式化和列对齐
:OfflineHelp tree            " 文件树
:OfflineHelp theme           " 颜色模式
:OfflineHelp clipboard       " 复制粘贴、鼠标、OSC52
:OfflineHelp limits          " 运行依赖与限制
```

主题支持 Tab 补全，帮助窗口内按 `q` 关闭，`/` 搜索、`Ctrl+]` 跳转、`Ctrl+t` 返回。
冒号补全菜单支持 `↑/↓` 选择；已选候选时第一次 Enter 只确认，再按一次才执行命令。
无菜单或未选择候选时 Enter 仍正常执行；单一候选被 Tab 直接补齐且菜单已关闭时也直接执行。
也可用原生 `:help offline`、`:help OfflineCompletionAll`；不覆盖当前编辑缓冲区，不修改或保存文件。

```vim
:OfflineCompletionAll off     " 当前会话全部补全关闭
:OfflineCompletionAll on      " 恢复关闭前的设置
:OfflineCompletionAll toggle  " 切换
:OfflineCompletionAll         " 只查询当前状态
```

总开关影响所有已加载及之后进入/打开的缓冲区：关闭自动弹窗、路径、正文单词、九类词库和
本包接入的 LSP 补全，同时暂停插入模式的 `Ctrl+n/p` 以及 `Ctrl+x` 补全入口，避免仍能手动触发。
`Ctrl+x` 前缀的其他用途也暂时不可用；普通模式按键和命令行补全不受影响，正文方向键和回车正常移动/换行。
恢复时还原选项和按键，不强行打开原先单独关闭的词库；LSP 诊断、悬浮和跳转不会被断开。
不写个人配置，退出重启后恢复默认；关闭期间不要另行修改补全选项/按键或重新加载配置，
否则恢复时可能覆盖这些修改。不接管额外安装的第三方补全插件或直接调用 `complete()` 的脚本。

已有 `:OfflineCompletion off` **仍然只关闭当前缓冲区的词库**，不等于总开关。
不再另设只关闭自动弹窗的 `OfflineAutocomplete` 命令，避免多个开关混淆。

### 自动补全与可选 LSP

使用 `-u ./nvim/examples/init.lua` 加载示例配置后，自动启用 Neovim 0.12 原生补全，
不新增补全插件、不联网安装依赖：

- **路径**：输入 `./`、`../` 后自动提示，相对当前编辑文件所在目录；新缓冲区没有文件名时
  回退到当前工作目录。`/` 按绝对路径、`~/` 按主目录查找，不改变 `:pwd`。
  目录候选带 `/`，确认后继续输入可补全下一层；只有输入 `.` 才列出隐藏文件。
- **正文**：从当前文件已有单词生成候选，不扫描其他文件或 tags。
- 停止输入约 150 ms 后弹出候选，**不预选、不自动插入**。`↓/↑` 或 `Ctrl+n/p` 选择，
  已选候选时 `Enter` 或 `Ctrl+y` 确认，`Ctrl+e` 取消；Enter 确认不换行。
  无菜单/未选择时 Enter 正常换行，方向键无菜单时正常移动，不修改原有 Tab 行为。
- 路径按 Linux 文件名区分大小写，不展开通配符、环境变量或 `~其他用户`。
  路径含空格、引号或转义时不保证完整识别，也不会按 Shell/JSON 等语法自动转义，需手动编辑。
  只列举当前一级目录；大型目录、慢速网络挂载仍可能影响响应。

#### 随包语言服务器

Python、JS/TS、YAML、JSON、Shell 的语言服务器**随包交付**，放在 `nvim/libexec/`。
配置按 nvim 的实际位置定位，不依赖 PATH、系统 Python 或系统 Node。每种语言按下表顺序取第一个可用的命令；
随包服务器不存在时（如在仓库里直接试用 `init-offline.lua`），再找 PATH 里的同类服务器；都没有就安静跳过，
保留路径和正文补全。

| 文件类型 | 随包服务器 | 实现与链接方式 | PATH 回退 |
| --- | --- | --- | --- |
| Python | ty 0.0.95：`libexec/ty server` | Astral 官方 musl 发布版，Rust，static-pie | `pyright-langserver --stdio` |
| JS / TS / JSX / TSX | TypeScript 7.0.2：`libexec/typescript/lib/tsc --lsp --stdio` | 微软官方发布版，Go 重写版，静态链接 | 无 |
| YAML | yaml-language-server 2.0.0 | 由随包静态 Node 26.13.0 运行 | `yaml-language-server --stdio` |
| JSON / JSONC | vscode-json-language-server（vscode-langservers-extracted 4.10.0） | 同上 | `vscode-json-language-server --stdio` |
| Shell / Bash | bash-language-server 5.8.1 | 同上 | `bash-language-server start` |
| Nginx / Lua / C、C++ | 不随包 | — | `nginx-language-server`、`lua-language-server`、`clangd` |

随包的 Node 是本仓库 `node-static/` 用 `configure --fully-static` 编出来的纯静态 ELF，发布在 fdoc 的
`tools/node/`，构建时按 `extras.json` 中固定的 URL 和 SHA-256 下载。运行包里只放 `libexec/node/bin/node`，
不带 npm。三个 Node 服务器在构建时用这个 Node 自带的 npm 执行 `npm ci`，按 `lsp-node/package-lock.json`
逐个校验 integrity，安装到 `libexec/lsp-node/node_modules/`。
它们全部是纯 JS 或 WebAssembly，安装后会检查没有 `.node` 原生扩展。静态 Node 不能加载 `.node`，这一点已实测确认。
安装时用 `--ignore-scripts` 跳过了安装脚本：依赖里只有 core-js 有 postinstall，内容是打印赞助信息。
`--no-bin-links` 不生成 `.bin` 软链接，配置直接用 node 执行各服务器的入口脚本。

**能用的功能（已在 scratch 断网环境和 glibc 宿主机上实测）：**

| 语言 | 补全 | 诊断 |
| --- | --- | --- |
| Python | 标准库成员（`os.pa` → `path`） | 类型错误（`count: int = "a"`） |
| TypeScript / JS | 内置类型成员、同一项目内其他文件的导出、`.js` 文件 | 类型错误 |
| YAML | Compose 文件按随包官方 schema 分层补全键名和部分枚举值；其他文件需指定本地 schema | 不符合 schema 的字段/值，以及 YAML 语法错误 |
| JSON | 只在指定了本地 schema 时补全键名 | 不符合 schema 的值，以及 JSON 语法错误 |
| Bash | 文件内定义的变量 | 未测试（需要 shellcheck，未随包） |

另外支持 `K` 悬浮说明、`gd` 跳转定义，以及 `Ctrl+x` 再 `Ctrl+o` 手动触发 LSP 补全，但这些没有单独做自动测试。
无 `.git` 的独立文件也允许启用。不配置保存时格式化、自动修复或自动写文件；格式化仍由上面的 conform 工具负责。
主动确认 LSP 候选时，服务器可能附带额外的文本编辑（如补充 import），可以用撤销检查。

**YAML、JSON 的补全依赖 schema。** 离线时 SchemaStore 查询和 schema 下载都已关闭，所以没有 schema 的文件
只有语法诊断，不能补全键名。

**随包 Compose schema：** 运行包的 `nvim/completion/schemas/compose.json` 是 compose-spec 提交 3a4a699 的官方 schema，
和 Compose 词库提取用的是同一份固定快照（SHA-256 见 `completion/sources.json`）。配置通过 `yaml.schemas` 把它关联到
`compose.yaml/yml`、`docker-compose.yaml/yml`，以及 `compose.override.yaml`、`docker-compose.prod.yml` 等文件，文件里不用写 schema。

改用 schema 是因为词库不分层级、也不校验；schema 只给当前层级的字段（比如在 `services.web` 下不会出现顶层的
`include`），会把未知字段、类型不对、不在枚举里的值报成诊断，也能补部分枚举值（如 `cgroup` 的 `host`、`private`）。

- **词库只兜底**：yaml 服务器附加到这个缓冲区之后，Compose 词库不再给出候选，避免菜单里同一个字段出现两次；
  服务器没有附加时（如随包服务器缺失、PATH 里也没有）仍用词库。词库里的中文说明只在兜底时看得到，
  想看时用 `:OfflineCompletion compose` 手动选择词库，`:OfflineCompletion auto` 恢复。
- **插入内容不同**：确认 LSP 候选时服务器会把冒号一起插入，比如 `container_name: `。词库只插入关键字本身。
- 实测 yaml-language-server 的值补全有空缺：服务下只有 `cgroup:` 一个键时没有候选，前面已有其他键时有候选。
- 打开文件后服务器刚附加时，第一次补全请求可能为空（schema 还在加载），约几秒后正常；继续输入会重新请求。
- schema 是 2026-10-24 取的快照，目标环境的 Docker Compose 比它新或旧都可能导致误报或漏报，最终以 `docker compose config` 为准。

**其他文件不用 schema 的原因：**

- opencode 的官方 schema 有现成快照，但其中 `model` 等字段用 `$ref` 引用 `https://models.dev/model-schema.json`
  （8935 个模型 ID 的枚举，经常变）。json 服务器遇到外部 `$ref` 会联网下载，`schemaDownload.enable = false` 拦不住；
  断网时报 `Unable to load schema`，联网时会访问 models.dev。把这张表做成快照又会很快过期、把新模型报成错误，
  所以 opencode 继续用词库，不关联 schema。这是构建内断网测试发现的，本机联网时下载成功、没有暴露。
- `daemon.json` 没有官方 schema；Nginx、systemd 等不是 YAML/JSON，都继续用词库。

其他文件需要按 schema 补全和校验时，在文件里指定本地 schema：

```yaml
# yaml-language-server: $schema=./schema.json
```

```json
{ "$schema": "./schema.json" }
```

相对路径基于当前文件所在目录，也可以用绝对路径。除 Compose 外，本包不附带其他 schema 文件。
自己指定的 schema 如果用 `$ref` 引用了外部 URL，服务器同样会去联网下载，离线时会报加载失败。

**配置上的取舍：**

- JSON：vscode-json-language-server 收到设置时会执行 `validateEnabled = !!json.validate.enable`，
  所以必须显式传 `json.validate.enable = true`，否则连语法错误也不报。VS Code 会自动传这个设置，Neovim 不会。
  `provideFormatter = false`，格式化仍用 jq / Biome。
- TypeScript：关闭自动类型获取（ATA，`disableAutomaticTypeAcquisition`、
  `tsserver.automaticTypeAcquisition.enabled = false`）。开启时它会调用 PATH 中的 `npm install @types/...`。
  这两个设置名取自 TypeScript 7.0.2 源码，是否确实生效没有单独测试。Node 项目的补全依赖项目自己的
  `node_modules` 里的类型，本包不会替项目安装。TypeScript 只读类型声明（`.d.ts`），不运行代码，
  也不找全局 `npm install -g` 的包或本机的 `node`。

  **Node 内置模块（`fs`、`process`、`require` 等）要两步：** 项目装 `@types/node`，**并且**在项目根目录写配置文件，
  JS 项目用 `jsconfig.json`，TS 项目用 `tsconfig.json`：

  ```json
  { "compilerOptions": { "types": ["node"] } }
  ```

  只装 `@types/node` 不够：TypeScript 7 不再自动加载 `node_modules/@types` 下的全部类型包，
  诊断会提示 `add 'node' to the types field in your tsconfig`。第三方包看包本身：自带类型的（如 axios）装上就能补；
  不带的（如 express 5）要另装 `@types/express`，它通过 import 加载，不需要写进 `types`。
  装了 `@types/express` 后，即使不写 `types`，Node 内置模块也能补全，因为它自己引用了 Node 类型，这不是通用做法。

  实测（Rocky 9.6，断网，`.js` 用 `require`、`.ts` 用 `import`，两者结果一致）：

  | 项目 | `fs.` / `process.` | axios | express | 数组等内置对象 |
  | --- | --- | --- | --- | --- |
  | 什么都不装 | 否 | 否 | 否 | 能 |
  | 装 `@types/node`、axios、express | 否 | 能 | 否 | 能 |
  | 同上，加 `"types": ["node"]` | 能 | 能 | 否 | 能 |
  | 再装 `@types/express` | 能 | 能 | 能 | 能 |
- Python：ty 按 `pyproject.toml`、`setup.py`、`setup.cfg`、`requirements.txt`、`.git` 识别项目根目录。
  第三方库补全要找到库所在的 site-packages。ty 自己只查找 `VIRTUAL_ENV`、`CONDA_PREFIX` 和项目根目录的 `.venv`，
  不使用 PATH 中的 `python3`。运维机上常见的是直接 `pip install` 到系统 Python，所以示例配置补了一步：
  - 没有 venv：执行一次 PATH 中的 `python3`，取 `site.getsitepackages()`（启用 user site 时再加
    `~/.local/lib/pythonX.Y/site-packages`），把 `sys.prefix` 和这些目录作为 `environment.python`、
    `environment.extra-paths` 传给 ty。
  - venv 用 `--system-site-packages` 创建：用这个 venv 的 python 取同样的目录。ty 自己只带上 `/usr/lib` 下的系统目录。
  - 独立 venv、Conda 环境不做处理，由 ty 自己查找。项目里有 `ty.toml` 或 `pyproject.toml` 的 `[tool.ty]`、
    或者有 `~/.config/ty/ty.toml` 时也不处理，以免覆盖用户自己的配置；只检查项目根目录，不检查上级目录。

  要单独执行 python 才能取目录，是因为 RHEL/Rocky 的 pip 默认装到 `/usr/local/lib/pythonX.Y/site-packages`，
  这个目录由发行版改过的 `site.py` 在运行时加入，ty 不运行 Python，按 `sys.prefix` 推算不到。
  执行时不加 `-I`、`-s`，因为加了以后 RHEL 不返回 `/usr/local` 目录；在 `/` 目录下执行，避免导入当前目录里的同名模块。
  每个 nvim 会话对每个解释器只执行一次，超时 3 秒；PATH 里没有 `python3` 时只补全标准库和项目内代码。
  传 `sys.prefix` 而不是解释器路径，是因为 uv 等工具安装的 `python3` 是软链接，ty 按链接位置推算出的前缀不对。
- Python 库本身没有类型注解时，模块成员能补全，但推不出函数返回值类型，比如 requests 2.34 之前的
  `requests.get()` 返回值后面补不出 `status_code`。装上对应的存根包（如 `types-requests`）就可以，
  存根装在 venv 或上面这些 site-packages 中都行。
- Bash：bash-language-server 的 shellcheck 诊断需要 PATH 里有 `shellcheck`（未随包）；
  悬浮显示命令说明会调用系统的 `bash`、`man`，scratch 测试里没有这些程序，只验证了补全。

**已知问题：**

- 退出 nvim 或停止客户端时，TypeScript 7 会在 shutdown 后输出 `context canceled` 并以退出码 1 结束，
  nvim 会提示 `Client offline_typescript quit with exit code 1`。这只出现在退出阶段，不影响使用。
- 运行包变大：x86_64 的 tar.gz 从约 53 MB 增加到约 150 MB，解压后约 475 MB。
  其中 Node 122 MB，`lsp-node` 135 MB，ty 32 MB，TypeScript 7 27 MB。`lsp-node` 中有 64 MB 是
  vscode-langservers-extracted 为 HTML/ESLint 等服务器引入的 TypeScript 4.9.5，JSON 服务器本身用不到；
  为了保持和 lockfile 一致，没有手动删除。
- 第三方服务器本身的联网行为：已关闭的只有上面列出的 schema 下载、SchemaStore 和 ATA。
  测试都在断网环境中进行，不承诺这些程序在联网环境中绝不发起请求。

`nginx.conf` 沿用 runtime 的文件类型识别。自定义名称的配置若未识别，可执行
`:set filetype=nginx`；不把所有 `.conf` 强制识别为 Nginx，也不要求额外项目配置文件。
Nginx 指令补全和说明需要上述服务器，缺少时不会凭空提供指令词库。
**编辑器 `./` 补全基准不等于 Nginx 的运行时路径解析规则**，配置最终仍需用目标环境
的 `nginx -t` 检查。

本地专项测试（`TEST_ROOT` 使用独立临时目录）：

```sh
TEST_ROOT=/tmp/opencode/nvim-completion TEST_LSP=1 \
  ./dist/x86_64/nvim/bin/nvim --headless -i NONE -u ./init-offline.lua \
  -c 'lua local ok,e=pcall(dofile,"test/completion-test.lua"); if not ok then print(e); vim.cmd("cquit 1") end'
```

`TEST_LSP=1` 使用本机 Python 3 运行本地模拟服务器，仅验证 LSP 协议接入与自动候选；
不设置该变量则只验证无需服务器的补全，不代表验证了真实 Nginx 语言服务器。

### 离线关键字：配置文件、Docker CLI 与 HTTP Headers

示例配置新增纯 Lua 词库来源，不要求 LSP、Node、Python 或联网。按文件名或文件类型选择词库，
输入关键字前缀后自动提示；只插入关键字，不自动加引号、冒号、等号或分号。
`↓/↑` 或 `Ctrl+n/p` 选择，已选候选用 Enter 或 `Ctrl+y` 确认、`Ctrl+e` 取消，
候选说明显示上下文、模块、语法和可选值。

| 词库 | 默认匹配 |
| --- | --- |
| OpenCode | `opencode.json`、`opencode.jsonc`；Schema 标记废弃的节点/分支不提取 |
| Compose | `compose.yaml/yml`、`docker-compose.yaml/yml` 及常见 override/prod 等后缀文件。yaml 服务器附加后只兜底 |
| Nginx | `nginx` 文件类型；常用开源 HTTP/stream 模块指令 |
| systemd service | `*.service`（含模板单元）、`*.service.d/*.conf`；字段名保留大小写 |
| Tomcat | `server.xml`；Tomcat 9.0.123 / 10.1.61 的元素名、属性名及 TLS 等常用组件 |
| Redis | `redis.conf`；Redis 8.10.2 官方样例中的配置指令，不含客户端命令 |
| dockerd CLI | Shell 当前行简单 `dockerd --选项`，支持 sudo/exec 前缀；本机 27.3.1 的 85 个长选项和 8 个短选项 |
| Docker daemon | `daemon.json`；Moby v27.3.1 Linux 的 80 个根字段和 25 个嵌套字段 |
| HTTP Headers | `.http` / `.rest` 头部区域及 Nginx 指定指令的头名称位置；MDN 固定来源的 74 个常用字段 |

**手工补录修改 `completion/custom/*.json`，不要改 generated 文件。** 安装后位于
`nvim/completion/custom/`；修改运行目录中的词库后执行 `:OfflineCompletionReload` 生效，无需重新编译。
自定义文件名用 `:OfflineCompletion compose` 等命令选择；`off` 只禁用词库，`auto` 恢复自动匹配。
仓库试用直接加载配置旁的 `completion/`，安装配置则从当前 nvim 安装目录定位；不读取工作目录的 Lua。

词库从随仓库固定的 Schema/XML、帮助/源码及 MDN 文档快照提取，更新时校验来源哈希，构建不自动联网更新词库。
常用项另有中文简释，其余沿用上游英文；generated 和 custom 合并，同名关键字在菜单里去重。
第一版**不解析层级**，上下文只作说明，不等同于 Schema/LSP 校验，部分复杂注释/多行值可能出现额外提示。
Compose 的分层补全和校验由上面的随包 schema 提供，词库只在 yaml 服务器没有附加时使用。
Tomcat 可区分元素/属性，支持 `<Con`、`</Con`、`<Connector maxT` 和跨行属性；不自动插入 XML 结构
或属性值，不按当前元素过滤所有属性。自定义 Redis 配置名使用 `:OfflineCompletion redis`。
Docker 特殊命令位置用 `:OfflineCompletion dockerd-cli`，自定义 JSON 文件名用
`:OfflineCompletion docker-daemon`。CLI 只补选项名，说明中保留本机帮助默认值和类型；
JSON 字段单独核对，不能直接从 CLI 去掉 `--`。不解析复杂 Shell/跨行语法，不校验 JSON 层级；
同一项同时出现在启动参数和 daemon.json 中可能导致启动失败。详见词库说明。
HTTP Header 名称大小写不敏感，只补名称，不补冒号或值，附中文说明和语法。
HTTP/REST 在请求/状态行后的头部提示，空行后视为正文，`###` 分隔下一次请求；
Nginx 自动模式支持 `add_header`、`add_trailer`、`proxy_set_header`、`proxy_hide_header`、`proxy_pass_header` 的首个参数。
普通文本片段可用 `:OfflineCompletion http-headers`，补录修改 `completion/custom/http-headers.json`。
不解析复杂模板/跨行 Nginx 指令，不混入 HTTP/2 伪首部；非标准代理头明确标注，废弃/实验性字段默认不收录。
模块、指令和枚举是否可用取决于目标版本及编译选项；最终仍用目标工具校验配置。
详见 [`completion/README.md`](completion/README.md) 的补录格式、维护命令、来源与许可说明。

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
  上述六种静态格式化工具和 Nginx Python 脚本随目录分发，并未编译进 nvim ELF；
  Nginx 依赖系统 `python3`，其他外部程序仍需另行提供。
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

示例 Neovim 配置默认启用真彩色，可用 `\c` 切换低色模式；默认关闭编辑器鼠标，把选择/右键交给终端。
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
7. 各格式实际输入输出、错误输入原文保留、XML 外部实体不展开、properties
    原文保留和 mini.align 列对齐；在 scratch 中直接调用随包静态程序，不需要 shell。
   JSONC 覆盖注释、尾逗号、键顺序、重复键/大整数文本保留、项目配置隔离、撤销及幂等性。
   Nginx 在有系统 Python 3 的环境验证格式化、撤销、幂等和进程失败保留正文；
   scratch 不附带 Python，仅验证依赖缺失提示及正文保留，不声称脚本能在 scratch 中运行。
8. OneDark 加载、`dark` 调色板、传统语法/Tree-sitter/文件树/缩进线高亮组，以及切换主题后
   重新加载；颜色模式循环切换、ANSI 关键高亮的基础色范围、淡色缩进线及 ANSI 关闭状态，
   同样纳入断网和 scratch 测试，不能代替实际终端的视觉确认。

构建与测试是否原生执行取决于执行主机：在 x86_64 主机上构建 arm64 使用模拟器，
在 aarch64 主机上构建 arm64 为原生执行；模拟器测试不能代替真实 ARM 机器测试。
自动测试不等于验证了所有实体终端：真彩色显示、鼠标手感、SSH/堡垒机链路、
桌面剪贴板落地和具体第三方插件仍需在实际客户端试用。

2026-10-22 已完成包含 OneDark 1.0.3 的双架构发布包构建：x86_64 在本机原生构建，
aarch64 在 `192.168.182.150` 原生构建，两端均使用默认 builder。
上述 Docker 断网功能测试、无系统 terminfo 的 PTY/tmux 测试及 scratch 测试均已通过，
包括 OneDark、文件树和格式化回归，不依赖模拟器测试结果。
`dist/` 中两种架构的运行包和源码包均已更新；实际客户端颜色显示仍需视觉确认。

2026-10-22 已将 `\c` 三档切换与淡色缩进线更新到双架构运行包和源码包：
x86_64 在本机、aarch64 在 `192.168.182.150` 原生构建，两端仅使用默认 builder。
两端 Docker 断网增强功能回归、无系统 terminfo 的 PTY/tmux 和 scratch 测试均已通过，
包括颜色循环切换、缩进线关闭/恢复、切换不改正文及文件树和格式化回归。
本机另已验证三档启动与实际快捷键映射；低色终端的实际观感仍需客户端确认。
构建上下文排除各级目录中的隐藏备份，避免测试备份混入源码包。

2026-10-23 接入 Nginx `nginxfmt.py`，使用系统 Python 3。本机使用已有 x86_64
静态程序与临时复制的完整运行目录，加载新配置和脚本，通过增强功能回归、Nginx
格式化/撤销/幂等/进程失败保留正文测试，以及空 PATH 下的依赖缺失测试。
此次尚未重新构建双架构或运行 Docker/scratch 测试，`dist/` 发布包尚未包含该改动。

2026-10-24 新增原生路径、当前文件单词自动补全及已有语言服务器的条件接入。
使用已有 x86_64 静态程序通过自动候选、路径确认/取消、空 PATH 运行和本地模拟 LSP
自动发现/接入测试，并通过已有主题、颜色切换和格式化增强功能回归。
本机未安装真实语言服务器；未验证真实 Nginx LSP、ARM 或本次 Docker/scratch 构建。
尚未重新构建双架构发布包；`dist/` 的示例配置尚未包含此次修改。

2026-10-24 接入 Biome 2.6.2 JSONC 格式化。双架构下载哈希与官方发布记录一致，
`readelf` 检查均无动态解释器和 NEEDED；x86_64 在本机原生测试，ARM 仅检查 ELF，尚未运行。
临时复制完整 runtime 后，通过 JSONC 和已有增强功能、补全/模拟 LSP 回归。
另在断网的隔离 chroot 中通过增强功能和 JSONC 测试：根文件系统不含系统共享库、Shell、
Node 或 Python，仅提供 proc 和 `/dev/null`；这是本地隔离测试，不是 Docker/scratch 构建。
本次未修改 `dist/`，未执行双架构完整构建或发布；正式包需后续重新构建。

2026-10-24 已重新构建包含 Nginx 格式化、原生路径/正文补全、可选 LSP 和 Biome 2.6.2
JSONC 格式化的双架构运行包、源码包。x86_64 在本机原生构建，aarch64 在
`192.168.182.150` 原生构建，均使用默认 builder；两端 Docker 断网功能、PTY/tmux、
scratch 测试及导出后的补全/本地模拟 LSP 回归通过。所有 ELF 均检查架构、动态解释器和 NEEDED。
运行包不混入测试或隐藏备份，源码包保留完整构建配置、测试、Biome 源码及原始二进制。
`dist/` 已更新；发布使用原有 `pushfdoc.sh`，仅上传两个运行包，源码包保留在 `dist/`。
真实第三方语言服务器和实际客户端的显示/交互仍需另行验证，不以模拟 LSP 测试代替。

2026-10-24 新增四类离线配置关键字词库及手工补录/重载。使用已有 x86_64 运行包的临时完整副本，
通过文件匹配、中文说明、同名合并、手工覆盖/禁用/重载、格式错误回退、原生菜单确认/取消、
路径/正文及模拟 LSP 共存测试；已有主题、颜色、文件树相关增强和 JSONC/Nginx 等格式化回归通过。
Python 提取测试及 `--check` 快照/生成结果比对通过。断网 chroot、空 PATH 下的增强回归通过；
本次未重新构建 Docker/scratch 或 ARM，未更新 `dist/` 或发布目录。

2026-10-24 增加 Tomcat server.xml 与 redis.conf 词库；手工补录分别位于
`completion/custom/tomcat.json` 和 `completion/custom/redis.json`。资料固定版本并校验哈希。
本机通过元素/属性区分、跨行 XML、结束标签、点号属性、Redis 指令位置、实际菜单确认、
路径/模拟 LSP 共存、提取脚本及原有完整 smoke 回归；断网且无 Shell/Node/Python 的 chroot 增强回归通过。
本轮未构建 Docker/scratch 或 ARM，不更新 `dist/` 或发布目录；实际 Tomcat/Redis 启动兼容性需目标版本另行检查。

2026-10-24 增加 dockerd CLI / daemon.json 两类词库，基于本机 `/usr/bin/dockerd`
27.3.1（41ca978）帮助和 Moby v27.3.1 Linux 配置源码。手工补录位于
`completion/custom/dockerd-cli.json`、`completion/custom/docker-daemon.json`。
使用已有 x86_64 运行包的临时完整副本，通过 9 项提取测试、八类词库专项、空 PATH 词库测试、
原有完整 smoke 回归及路径/模拟 LSP 共存的实际菜单确认测试；本轮未做 ARM 或 Docker 隔离测试。
仅本地接入，未重新构建或发布；未读取现有 daemon.json，未启动或重启 Docker。

2026-10-24 在上述八类词库接入后，已使用默认 builder 完成双架构运行包和源码包打包；
x86_64 本机原生构建，aarch64 在 `192.168.182.150` 原生构建。两端 PTY/tmux、断网 scratch、
八类词库和实际菜单回归通过，导出包已检查架构、静态 ELF、词库与源码快照完整性，未发布。

随后新增第九类 HTTP Headers，资料固定到 MDN content 提交 `bd5271a96d81`，包含 74 个常用字段。
使用 x86_64 运行包的临时完整副本，通过 11 项提取测试、九类词库专项、空 PATH 测试、
原有完整 smoke 回归及路径/模拟 LSP 共存的实际菜单确认；断网、无 Shell/Node/Python 的 chroot 增强回归通过。
未做本轮 ARM、真实 HTTP 客户端或实际 Nginx 请求行为验证；词库测试不代替目标服务的协议/配置检查。
本轮仅本地接入和测试，未重新打包或发布；当前 `dist/` 仍是八类词库版，不包含 HTTP Headers。

2026-10-24 增加原生中文帮助 `doc/offline.txt`、`:OfflineHelp [主题]` 和
`:OfflineCompletionAll [on|off|toggle]` 会话补全总开关，文档已覆盖与单缓冲区词库开关的区别。
使用 x86_64 运行包临时完整副本，通过帮助标签/主题/关闭窗口、原编辑内容不变、开关重复调用、
新建/已有/删除缓冲区、选项和 Lua 按键恢复、实际菜单关闭/手动入口拦截、LSP 关闭期间附加与迟到响应测试。
原有完整 smoke 和断网、无 Shell/Node/Python 的 chroot 增强回归通过；词库生成检查和 11 项提取测试通过。
构建文件已接入帮助文档的运行包/源码包路径；本轮未完整构建或验证 ARM，未更新 `dist/` 或发布目录。
现有压缩包尚不包含 HTTP Headers、本帮助和补全总开关，需要后续重新构建。

上述 HTTP Headers、帮助和总开关随后已完成双架构原生构建并发布：本机 x86_64、
`192.168.182.150` 原生 aarch64，均使用默认 builder，发布包哈希与本地一致。

本轮新增正文与冒号命令菜单的上下键选择、Enter 条件确认，保留 Tab、正常换行和命令历史。
本机 Neovim 输入事件测试覆盖弹出/横向命令菜单、两次 Enter 执行、无选择/单候选处理、
路径/Header/模拟 LSP 共存、补全总开关关闭后的回退；原有完整 smoke 和断网、无 Shell/Node/Python
的 chroot 菜单回归通过。帮助和词库说明已同步，11 项提取测试与生成检查通过。
本轮未重新构建、验证 ARM 或发布；当前 `dist/` 和已发布运行包仍是上一轮版本，不包含这些新按键映射。

2026-10-27 `\c` / `:OfflineColor` 的选择写入 state 目录 `offline-color`，下次启动沿用；
`NVIM_OFFLINE_COLOR` 仍优先且不写入。测试新增：切换后记录内容、重启后沿用、环境变量覆盖不改记录、
无效记录回退 truecolor。随后已用默认 builder 完成双架构原生构建：x86_64 在本机，aarch64 在
`192.168.182.150`；两端 Docker 断网功能、重启记录、PTY/tmux 及 scratch 测试通过，
导出包已检查 ELF 架构、无动态解释器和 NEEDED，运行包不含测试或备份。`dist/` 已更新，由用户自行发布。

2026-10-30 示例配置开启当前行/列底色，普通/插入模式红色光标、可视模式红色下划线光标，
加深 OneDark 选区颜色。本机 x86_64 现有运行包 + PTY 验证：truecolor 发送 OSC 12 `#ff3b30`、
退出发送 OSC 112，模式切换发送块/竖线/下划线光标形状；256/ANSI 不发送光标颜色。
随后用默认 builder 完成双架构原生构建：x86_64 在本机，aarch64 在 `192.168.182.150`；
两端解压运行包跑完整 smoke（headless + PTY/tmux 4 种 TERM）通过，ELF 架构正确、无动态解释器和
NEEDED，运行包不含测试文件。已发布，旧包备份为 `.pre-release-2026-10-30-09-24-36`。
未在实际终端/tmux 中目测光标颜色。`dist/SHA256SUMS` 不由 build.sh 生成，未更新。

2026-10-31 光标移动卡顿排查：原因是 `cursorcolumn` 每步重画整窗，不是补全词库。示例配置改为默认关闭
当前列底色，`\l` 临时开关，保留当前行底色。本机 x86_64 用现有 `dist/` 二进制加仓库内新配置测试：
tmux 200×50、3000 行 Nginx 配置，每次移动由约 2.5 ms 降到约 0.1 ms；`enhancements-test.lua` 通过。
随后用默认 builder 完成双架构原生构建：x86_64 在本机，aarch64 在 `192.168.182.150`；两端容器内
完整 smoke（headless + PTY/tmux 4 种 TERM、断网 scratch 测试）通过，ELF 架构正确、无动态解释器和 NEEDED，
运行包内 `examples/init.lua` 与仓库一致，不含仓库测试文件。`dist/` 已更新，未发布；`dist/SHA256SUMS` 未更新。
未在真实目标机 SSH 链路上实测卡顿改善。

2026-11-03 随包语言服务器：新增 ty 0.0.95、TypeScript 7.0.2、静态 Node 26.13.0（来自本仓库 `node-static/`，
发布在 fdoc `tools/node/`）和三个 Node 服务器。双架构都用默认 builder 原生构建：x86_64 在本机，aarch64 在
`192.168.182.150`，没有用模拟器。构建内原有完整测试全部通过，新增的 `test/lsp-bundled-test.lua` 在
`FROM scratch` 断网阶段运行（没有 shell、libc、Python、系统 Node），5 种服务器的补全和诊断全部通过。
两台 Fedora 44 宿主机（glibc）上，把 tar 包解压到临时目录（移动过安装位置），用 `env -i` 清空环境变量，
PATH 指向不存在的目录，再跑同一测试：全部通过。x86_64 宿主机测试用的是文档定稿前的那次构建，
和最终产物只差 README/帮助文本。两个包中 nvim、ty、tsc、node、biome、ruff、jq 均为对应架构的 ELF，
无 INTERP、无 NEEDED；没有软链接，没有 `.node` 文件，不含测试文件；`examples/init.lua`、`offline.txt` 与仓库一致。
tar.gz：x86_64 约 150 MB，aarch64 约 144 MB。未验证：真实目标机、悬浮说明和跳转、带第三方依赖的
Python 虚拟环境、带 `@types/node` 的 Node 项目、shellcheck 诊断。`dist/` 已更新，未发布。

2026-11-03 Python 第三方库补全：ty 不使用 PATH 中的 python3，系统 pip 安装的库补不出来。示例配置改为在
没有 venv（或 venv 带 `--system-site-packages`）时，用该 python 的 `site.getsitepackages()` 设置
`environment.python`、`environment.extra-paths`。在 Rocky 9.6 x86_64（Python 3.9，requests 2.32.5 装在
`/usr/local/lib/python3.9/site-packages`）上测试：修改前 ty 找不到 requests，`ty.toml` 只写 `python = "/usr/bin/python3"`
也不行；修改后没有 venv 和 `--system-site-packages` 的 venv 都能补全 `Session`、`get`、`headers`；
项目 `.venv`、项目已有 `ty.toml` 时行为不变；PATH 中没有 python3 时只有标准库补全。requests 2.32.5 没有类型注解，
`requests.get()` 返回值的成员需要 `types-requests`，装上后通过。本机 Fedora 44 x86_64（系统 Python 3.14、
uv 安装的 Python 3.14 软链接）和 `192.168.182.150` Fedora 44 aarch64 原生测试同样通过。
双架构用默认 builder 原生重建，构建内全部测试通过，ELF 架构正确、无 INTERP/NEEDED，运行包中的
`examples/init.lua`、`offline.txt` 与仓库一致；新的 x86_64 包在 Rocky 机器上复测通过。
已发布到 fdoc `tools/neovim/`，与 `dist/` 逐字节比较一致；旧包备份为 `.pre-release-2026-11-03-13-19-23`。
测试是 headless 下直接发补全请求，未在终端交互确认菜单显示；Debian 系 `dist-packages` 和 `pip install --user` 未测试。

2026-11-03 Compose 改用随包官方 schema：`completion/sources/compose.json`（compose-spec 3a4a699）装到
`nvim/completion/schemas/`，通过 `yaml.schemas` 按文件名关联；yaml 服务器附加后 Compose 词库只兜底。
原计划 opencode 同样处理，构建内断网测试发现其 schema 引用 `https://models.dev/model-schema.json`，
json 服务器会联网下载（本机联网时下载成功，未暴露），改为继续用词库，测试中加了反向检查。
`test/lsp-bundled-test.lua` 新增：服务级字段补全、顶层不出现 `container_name`、`cgroup` 枚举值、`servics` 未知字段诊断、
`docker-compose.prod.yml` 匹配、`other.yaml` 不匹配、词库让位和手动选择；opencode 仍由词库补全且无 schema 诊断。
本机用 `unshare -n`（只有回环网卡）先跑通；插入模式实际按键确认候选，插入 `container_name: `，菜单无重复候选。
双架构用默认 builder 原生构建（x86_64 本机，aarch64 `192.168.182.150`），构建内全部测试通过；ELF 架构正确、
无 INTERP/NEEDED，包内 `completion/schemas/compose.json` 与仓库快照一致，`examples/init.lua`、`offline.txt` 与仓库一致。
新 x86_64 包在 Rocky 9.6 断网命名空间复测通过；发现服务器刚附加时第一次请求为空，几秒后正常，已写入说明。
`dist/` 已更新；源码包中的 README 不含"第一次请求为空"这一条和本段记录（构建后补写）。
已发布到 fdoc `tools/neovim/`，与 `dist/` 逐字节比较一致；旧包备份为 `.pre-release-2026-11-03-15-37-39`。

2026-11-03 Node.js 补全实测：在 Rocky 9.6 上用上面发布的 x86_64 包、`unshare -n` 断网，测试项目依赖事先用 npm 装进各自的
`node_modules`（@types/node 26.6.6、axios 1.21.0、express 5.3.0、@types/express 5.0.6）。结果见“配置上的取舍”中的表：
发现只装 `@types/node` 不能补全 Node 内置模块，需在 jsconfig/tsconfig 写 `"types": ["node"]`。只改了 README 和
`offline.txt` 的说明，配置未改。测试目录已清理。双架构原生重建（x86_64 本机，aarch64 `192.168.182.150`），
构建内全部测试通过，ELF/INTERP/NEEDED 检查正常，包内 `offline.txt` 与仓库一致；已发布到 fdoc `tools/neovim/`，
与 `dist/` 逐字节一致，旧包备份为 `.pre-release-2026-11-03-16-04-56`。

## Reference Documentation

- [本包使用的 nginxfmt.py](https://fdoc.epoint.com.cn:3366/tmp/.liuwenru/tools/nginxfmt.py)、[原项目](https://github.com/slomkowski/nginx-config-formatter)

- [官方静态构建说明](https://neovim.io/doc/build/#build-static-binary-linux)
- [0.12.6 官方发布页](https://github.com/neovim/neovim/releases/tag/v0.12.6)
- [该版本构建说明](https://github.com/neovim/neovim/blob/v0.12.6/BUILD.md)
- [固定依赖和校验值](https://github.com/neovim/neovim/blob/v0.12.6/cmake.deps/deps.txt)
- [终端说明](https://neovim.io/doc/user/term.html)
- [剪贴板 provider 与 OSC 52](https://neovim.io/doc/user/provider.html#clipboard-osc52)
- [原生离线 packages](https://neovim.io/doc/user/pack.html)
- [原生自动补全与 complete-functions](https://neovim.io/doc/user/insert.html#ins-autocompletion)
- [词库固定来源与校验值](completion/sources.json)、[词库维护说明](completion/README.md)
- [OpenCode V2 配置](https://opencode.ai/v2/docs/config)、[配置 Schema](https://opencode.ai/config.json)
- [Compose 官方 Schema](https://github.com/compose-spec/compose-spec/blob/main/schema/compose-spec.json)
- [Nginx 指令索引](https://nginx.org/en/docs/dirindex.html)
- [systemd service](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html)
- [Tomcat 9 配置](https://tomcat.apache.org/tomcat-9.0-doc/config/)、[Tomcat 10.1 配置](https://tomcat.apache.org/tomcat-10.1-doc/config/)
- [Redis 8.10.2 官方配置样例](https://github.com/redis/redis/blob/8.10.2/redis.conf)
- [Moby v27.3.1 daemon 配置定义](https://github.com/moby/moby/tree/v27.3.1/daemon/config)
- [MDN HTTP Headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers)、[固定内容源码](https://github.com/mdn/content/tree/bd5271a96d814ed6876e974186c465f1b3959e07/files/en-us/web/http/reference/headers)
- [内置 LSP 配置与补全](https://neovim.io/doc/user/lsp.html)
- [Nginx 语言服务器接入参考](https://github.com/neovim/nvim-lspconfig/blob/master/lsp/nginx_language_server.lua)
- [ty 0.0.95 发布页](https://github.com/astral-sh/ty/releases/tag/0.0.95)、[ty 文档](https://docs.astral.sh/ty/)
- [TypeScript 7.0.2（typescript-go）发布页](https://github.com/microsoft/typescript-go/releases/tag/typescript%2Fv7.0.2)、[LSP 启动参数源码](https://github.com/microsoft/typescript-go/blob/typescript/v7.0.2/cmd/tsgo/lsp.go)、[ATA 设置源码](https://github.com/microsoft/typescript-go/blob/typescript/v7.0.2/internal/ls/lsutil/userpreferences.go)
- [yaml-language-server 2.0.0](https://github.com/redhat-developer/yaml-language-server)（[modeline 指定 schema](https://github.com/redhat-developer/yaml-language-server#using-inlined-schema)）
- [vscode-langservers-extracted 4.10.0](https://github.com/hrsh7th/vscode-langservers-extracted)、[JSON 服务器设置说明](https://github.com/microsoft/vscode/blob/main/extensions/json-language-features/server/README.md)
- [bash-language-server 5.8.1](https://github.com/bash-lsp/bash-language-server)
- [静态 Node 构建说明](../node-static/README.md)、[npm ci](https://docs.npmjs.com/cli/commands/npm-ci)
- [nvim-tree 固定版本](https://github.com/nvim-tree/nvim-tree.lua/releases/tag/nvim-tree-v1.19.0)
- [nvim-tree 文档](https://github.com/nvim-tree/nvim-tree.lua/blob/nvim-tree-v1.19.0/doc/nvim-tree-lua.txt)
- [conform.nvim 文档](https://github.com/stevearc/conform.nvim/tree/v9.1.0)
- [缩进参考线](https://github.com/lukas-reineke/indent-blankline.nvim/tree/v3.10.1)
- [mini.align](https://github.com/nvim-mini/mini.align/tree/v0.18.0)
- [OneDark 固定版本及配置说明](https://github.com/navarasu/onedark.nvim/tree/v1.0.3)
- [shfmt](https://github.com/mvdan/sh/releases/tag/v3.14.1)、[yamlfmt](https://github.com/google/yamlfmt/releases/tag/v0.21.0)
- [jq](https://github.com/jqlang/jq/releases/tag/jq-1.8.2)、[Ruff](https://github.com/astral-sh/ruff/releases/tag/0.17.1)
- [Biome 2.6.2 固定发布](https://github.com/biomejs/biome/releases/tag/%40biomejs/biome%402.6.2)、[独立 musl 程序](https://biomejs.dev/installation/install-biome/#standalone-executable)、[format 参数](https://biomejs.dev/reference/cli/#biome-format)
- [libxml2 源码](https://download.gnome.org/sources/libxml2/2.15/)、[xmllint 手册](https://gnome.pages.gitlab.gnome.org/libxml2/xmllint.html)

分发包保留 Neovim LICENSE 和依赖顶层许可文件；同时导出匹配版本的源码包，
包含原始 Neovim 源码、固定依赖归档及构建脚本。需要再分发时，请同时提供对应源码包，
遵守依赖许可（尤其静态链接的 unibilium LGPL 对修改、重新链接等权利的要求）。
