# zsh-completion-lite

`../bash-completion-lite/` 全部补全规则（23 项，LVM 一项覆盖 44 个命令）的 zsh 版本，写成原生 zsh 补全函数（compsys），
不是用 `bashcompinit` 套用 bash 脚本。查询逻辑、只读限制和超时与 bash 版一致。

- 默认使用本目录的规则：zsh 自带或系统提供了同名命令的补全时（如 `_git`、`_tmux`、`_ssh`），
  也由这里的规则替换。需要保留 zsh 自带补全的命令用 `MINI_ZSH_OFFICIAL_COMPLETION` 指定。
- 在本机 zsh 5.9（Fedora 包，`/bin/zsh`）上测试。

## 加载

推荐复制到用户目录（发布包不含 `test/`）：

```zsh
mkdir -p ~/.local/share
cp -R zsh-completion-lite ~/.local/share/
```

在 `~/.zshrc` **末尾**加入（放在 `compinit`、oh-my-zsh 等框架之后）：

```zsh
[[ -r ~/.local/share/zsh-completion-lite/init.zsh ]] &&
    source ~/.local/share/zsh-completion-lite/init.zsh
```

重新打开 shell（`exec zsh`），然后检查：

```zsh
print $_comps[git] $_comps[docker]    # 输出 _mini_git _mini_docker
kill -9 <Tab>
```

`init.zsh` 的工作：

1. 只在交互式 shell 中生效；路径按 `init.zsh` 自身所在位置计算，目录可以放在任何地方。
2. `compdef` 不存在（还没执行过 `compinit`）时执行 `compinit`。
3. 把 `functions/` 加到 `fpath` 最前面，对其中每个首行为 `#compdef 命令...` 的 `_*` 文件
   执行 `autoload` 和 `compdef`，覆盖之前注册的同名命令补全。

为什么要放在 `.zshrc` 末尾：之后再执行的 `compinit` 会从 `~/.zcompdump` 重新载入整个 `_comps`，
把这里的注册覆盖掉。

保留 zsh 自带补全（在 `source` 之前设置，空格分隔命令名）：

```zsh
MINI_ZSH_OFFICIAL_COMPLETION='git tmux'
source ~/.local/share/zsh-completion-lite/init.zsh
```

使用 `../zsh-bash-static/` 的静态 zsh 时，先 `source` 它的 `init.zsh`（提供 zsh 函数库并执行
`compinit`），再 `source` 本目录的 `init.zsh`。

## 已提供的补全

| 命令 | 范围（与 bash 版相同的部分见 bash 版 README） |
| --- | --- |
| `kill` | PID |
| `find`、`grep`、`rg`、`sed`、`awk`、`xargs`、`tar` | 常用选项、选项取值、路径、命令名 |
| `systemctl`、`journalctl` | 子命令、选项取值、本机单元名（支持 `--user`）、启动编号 |
| `nslookup` | 选项、`-type=` 查询类型、`/etc/hosts` 主机名 |
| `iptables`、`ipset`、`nft` | 表/链/集合、集合类型和参数、已有成员，只读查询 |
| `scp`、`sshfs` | Host 别名（`[user@]host:`）、本地路径、`-o` 选项及取值；不连远程 |
| `docker`、`docker-compose` | 子命令、本机容器/镜像/网络/卷、`docker cp` 容器内路径、Compose 服务和 profile |
| `lsof` | 选项、PID、用户、`-iTCP:443` / `-sTCP:LISTEN` |
| `git` | 子命令和别名、选项、分支/标签/远程分支、`A..B`、`push src:dst`、改动文件、stash、配置项名 |
| `tmux` | 子命令/别名/选项、`-t` 会话窗口窗格、缓冲区、键表、选项名、hook 名 |
| `nmcli` | `nmcli --complete-args` 的结果；nmcli 太旧时用内置简化规则 |
| `lvm` 及 43 个 `pv*`/`vg*`/`lv*` 命令 | 本机 LVM 选项和取值、PV/VG/LV 名、可用磁盘、`lvs -o` 字段 |

每条规则的查询命令、超时、只读边界和已知限制与 bash 版相同，详见
`../bash-completion-lite/README.md` 的“依赖和边界”。

## 与 bash 版的差异

- **分词**：zsh 按 shell 语法分词，冒号、等号不拆词，引号和反斜杠由 zsh 处理并在插入时按当前引号转义。
  bash 版为 `COMP_WORDBREAKS`、手工拆分命令行写的代码在这里都不需要（`ipset`、`nmcli`、`docker cp`、
  `docker-compose`、`sshfs`、`git`、`tmux`）。
- **git**：bash 版找到系统的 git-completion.bash 就改用它；这里按“默认用自带规则”替换 zsh 的 `_git`，
  行为与 bash 版自带规则一致。zsh `_git` 覆盖的子命令和选项更全（它也只查询本地仓库），
  需要时设 `MINI_ZSH_OFFICIAL_COMPLETION=git`。
- **scp**：zsh 自带的 `_ssh` 在 `host:` 之后通过 SSH 连接补全远程路径（`_remote_files`），
  可能卡住或触发认证；这里不连接远程。
- **tar**：zsh 自带的 `_tar` 解包/列出时对归档执行 `tar t` 列出成员，大的压缩包会等待；这里不打开归档。
- **nmcli**：nmcli 不支持 `--complete-args` 时使用内置简化规则；zsh 自带的 `_networkmanager`
  可用 `MINI_ZSH_OFFICIAL_COMPLETION=nmcli` 启用。
- **重定向**：`docker save ... > 文件`、`docker load < 文件` 由 zsh 自己补全文件，不经过这里的规则。
- **sudo**：`sudo docker stop <Tab>` 经 zsh 的 `_sudo` 转到这里的 docker 规则。
- **目录**：目录候选用 `_path_files -/`，只列目录；zsh 自动在目录后加 `/`。`docker cp` 容器内的目录
  加 `/` 不加空格，文件后加空格。
- 移植时发现并修正的两个问题（bash 版已同步修正）：
  - `journalctl -b`：新版 systemd 的 `--list-boots` 有 `IDX ...` 表头，这里只取数字编号。
  - `docker image rm|inspect|history|save|tag`：原先因已有二级子命令而不补全镜像名。
- `ipset` 的 `del`/`test` 最多列出 1000 个成员，可用环境变量 `MINI_IPSET_MAX_MEMBERS` 修改。

## 运行依赖

- zsh 和它的补全函数库（`compinit`、`_files`、`_path_files`、`_command_names`、`_users`、`_groups`、
  `_sudo` 等，发行版 zsh 包自带，位于 `/usr/share/zsh/<版本>/functions`）。只有 zsh 单文件、没有函数库时
  `init.zsh` 提示 `compinit not found` 并退出，不注册任何补全。
- 外部命令与 bash 版相同：`awk`、`ps`、`cat`；动态候选需要对应命令存在和读取权限；
  `timeout`（支持 `-k`）可选，没有时查询不限时，`docker cp` 容器查询和 Compose 查询跳过。
- 不需要 Python、网络或其他补全框架。
- 已知限制：
  - `fpath` 中的目录被 `compinit` 检查（compaudit）时要求不可被组/其他用户写入。
    `cp -R` 在 umask 022 下得到 755/644；从带 ACL 的源码仓库 `cp -a` 会保留组可写，
    若之后有其他 `compinit` 运行，会提示 insecure directories。
  - 修改 `functions/` 中的文件后需要重新打开 shell（或 `unfunction _mini_xxx; autoload -Uz _mini_xxx`）。

## 添加自己的补全

把 zsh 补全函数放进 `functions/`，文件名以 `_` 开头、首行为 `#compdef 命令`，`init.zsh` 会注册它：

```zsh
kubectl completion zsh > ~/.local/share/zsh-completion-lite/functions/_kubectl
```

只有 bash 补全脚本时可用 zsh 自带的 bash 兼容层（只支持 `complete`/`compgen` 的常见用法）：

```zsh
autoload -Uz bashcompinit && bashcompinit
source /path/to/xxx.bash
```

## 排查

```zsh
print $_comps[docker]          # 实际使用的补全函数
whence -v _mini_docker         # 函数来源
MINI_ZSH_OFFICIAL_COMPLETION=  # 确认未把命令留给 zsh 自带补全
```

按 `Ctrl-X h`（`_complete_help`）可查看当前位置的补全上下文。

## 自测

测试只在源码仓库中。在任意目录运行：

```zsh
zsh test/completions.zsh
```

测试用 `zsh/zpty` 启动真实的交互式 zsh，按 README 的方式把项目复制到临时 HOME 并 `source init.zsh`，
对每行输入按 Tab；`compadd` 被替换为记录候选，每次补全先写一条标记证明 Tab 确实被处理。
动态命令（docker、git、ipset、lvm、nmcli、tmux 等）用 `test/mocks.zsh` 中的 shell 函数代替，
不访问真实服务、防火墙、容器或网络。另外检查：未安装 `timeout` 时的行为、`init.zsh` 自己执行
`compinit`、`MINI_ZSH_OFFICIAL_COMPLETION=git` 保留 zsh 的 `_git`。临时目录在 `$TMPDIR`（默认 `/tmp`）
下创建，结束后删除。

## 参考文档

- [zsh Completion System（compsys、compinit、compdef、_files 等）](https://zsh.sourceforge.io/Doc/Release/Completion-System.html)
- [zsh Completion Widgets（compadd、compset、PREFIX/IPREFIX、words/CURRENT）](https://zsh.sourceforge.io/Doc/Release/Completion-Widgets.html)
- [zsh/zpty 模块](https://zsh.sourceforge.io/Doc/Release/Zsh-Modules.html#The-zsh_002fzpty-Module)
- 各命令的参考文档见 `../bash-completion-lite/README.md`。

规则中固定写入的列表（tmux 3.8 命令表、选项名等）与 bash 版相同；其余候选在按 Tab 时由本机命令给出，
跟随本机版本。
