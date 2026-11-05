# bash-completion-lite

一套可复制到运维主机的轻量 Bash 补全入口：

- 系统已经安装 `bash-completion`：复用官方按需加载器。
- 没有安装：使用自带 `_mini_completion_loader` 按需加载。
- 已有其他默认补全器：不覆盖它，只预加载本目录的规则。
- Bash 不支持 `complete -D`：自动退化成预加载。

## 已提供的补全

每个命令一个文件，位于 `completions/`；无需安装完整 `bash-completion`。

| 命令 | 支持范围 |
| --- | --- |
| `kill` | PID（原有规则） |
| `find` | 常用表达式、文件类型、用户/组、路径，`-exec` 后的命令名 |
| `grep` | 常用选项、颜色/目录处理模式、文件路径 |
| `systemctl` | 常用子命令、选项、单元类型/状态、本机单元名，支持 `--user` |
| `journalctl` | 常用选项、日志级别、输出格式、本机单元名、启动编号 |
| `rg` | 常用选项、颜色/引擎、从 `--type-list` 获取文件类型、路径 |
| `nslookup` | 常用选项、`-type=` 等查询类型、`/etc/hosts` 中的主机名 |
| `iptables` | 常用选项、表、内置链/用户链、协议、网卡、目标、连接状态 |
| `ipset` | 常用子命令、已有集合名、本机支持的集合类型、按类型的创建参数、按目标集合实际选项的添加参数、`del`/`test` 的已有成员、输出格式和文件路径 |
| `nft` | 常用操作、对象、协议族、已有表/链/集合、部分规则关键字 |
| `scp` | 常用选项、SSH 配置中的 Host 别名、本地路径 |
| `docker` | 常用子命令/选项、本机容器/镜像/网络/卷名，`cp` 两端的本地/容器路径，`load -i`/`--input=`、`save -o`/`--output=` 和 `<`、`>` 重定向后的本地文件，部分二级子命令 |
| `docker-compose` | 独立命令的常用子命令/选项、Compose/环境文件路径、项目目录、服务名和 profile |
| `lsof` | 常用选项、PID、用户、协议/端口示例、TCP 状态、路径 |
| `sed` | 常用 GNU 选项、脚本文件和输入文件路径 |
| `awk` | 通用短选项 `-F`、`-v`、`-f`、`-W`，文件路径 |
| `xargs` | 常用选项、命令名、`-a` 文件及命令后的本地路径 |
| `tar` | 常用选项、`-xzvf` / `xzvf` 组合、归档/输入文件路径、`-C` 目录、格式和引用风格 |
| `git` | 系统自带 git 官方补全时直接使用官方补全；否则使用自带规则：子命令和别名、各子命令选项、分支/标签/远程分支、`A..B` 区间、远程名、`push`/`fetch`/`pull` 的远程分支、已修改/已暂存文件、stash、`remote`/`stash`/`worktree` 等二级子命令、配置项名 |
| `tmux` | 子命令及别名、各子命令的选项，`-t`/`-s` 后的会话/窗口/窗格/客户端，缓冲区名、键表、选项名、hook 名、布局名，开关型选项的 `on`/`off`，目录、文件和命令名 |
| `lvm` | `lvm` 子命令及 `pvs`/`vgs`/`lvs`、`lvcreate`/`lvextend`/`vgextend` 等 43 个 LVM 命令：本机 LVM 支持的选项、`y|n`、`--type`、`--alloc` 等可选值，PV/VG/LV 名称，`pvcreate`/`vgcreate`/`vgextend` 的空闲磁盘，`lvs -o` 字段名 |

### 依赖和边界

- 面向 Linux Bash；使用 Bash 内建补全和系统常见的 `awk`、`cut`、`ps`。
  不需要 Python、网络服务或其他补全框架。测试中也不要求安装这些命令。
- 动态候选依赖对应命令存在及当前用户的读取权限；查询失败不显示错误，
  不运行 `sudo`，不启动服务、启动/停止容器或修改防火墙规则。
  `docker cp` 容器路径补全会在运行中的容器内启动只读目录查询进程，详见下文。
- 服务、Docker 和防火墙候选在按 Tab 时查询，不缓存；对象很多或本机服务
  响应缓慢时可能有等待。`iptables` 读取使用最多 1 秒的锁等待。
- Docker 仅查询本地 Unix socket，显式指定 `--host`/`-H`、`--context`，
  设置 `DOCKER_CONTEXT`，或 `DOCKER_HOST` 不是 Unix socket 时不查询对象。
  未指定端点时固定读取 `/var/run/docker.sock`，不跟随配置中的默认远程 context。
  容器、镜像、网络、卷的名称/ID 查询有 `timeout -k 1 2` 时限：2 秒未返回放弃，
  再过 1 秒强制结束客户端，daemon 卡住时按 Tab 最多等约 3 秒。
  宿主机没有 `timeout` 时这些查询照常执行，但不限时（`cp` 的容器查询则直接跳过）。
- `docker exec` 和 `docker container exec` 补全运行中容器的短 CONTAINER ID
  （来自 `docker ps --format '{{.ID}}'`），支持 `-it`、`--user root` 等选项后的
  ID 补全；其他原有按容器名称补全的子命令保持不变。
- `docker inspect` 和 `docker container inspect` 同时补全容器短 ID 和名称
  （来自 `docker ps -a`，包括已停止的容器），可连续补多个容器。
  `docker inspect` 也能查看镜像、网络、卷，但这里只补全容器。
- `docker cp`（包括 `docker container cp`）支持源端和目标端的路径补全：
  未输入冒号时提供本地路径及容器短 ID 和名称（带 `:`，来自
  `docker ps -a`，包括已停止的容器）；输入 `容器:/路径` 后列出容器内目录。
  已停止的容器只能补出名称/ID，容器内路径需要手写。目录候选带 `/`，支持隐藏文件、
  普通含空格路径、反斜杠转义和单/双引号；容器内相对路径按 `/` 解析。
  按 Tab 会执行 `docker exec … ls -1Ap -- 目录`，失败时尝试 `busybox ls`，
  不需要容器内的 Bash、`sh` 或 `find`。容器需处于运行状态且当前容器用户有读取权限。
  宿主机需有支持 `-k` 的 `timeout`（GNU 或相应 BusyBox 实现）；没有时仍可补全
  本地路径，但不查询 `cp` 的容器 ID/路径。每次查询限时 2 秒，额外 1 秒后强制
  结束本地客户端；超时不再尝试 BusyBox，普通失败可能再查询一次。
  超时只约束本地 Docker 客户端，不保证容器中的查询进程同步结束。
  不支持含换行的文件名，不判断指向目录的符号链接，超大目录仍可能产生较多输出。
- `scp` 不查询远程路径，不解析 SSH `Include`、通配 Host 或哈希 known_hosts。
  SSH 别名来自 `~/.ssh/config` 和 `/etc/ssh/ssh_config`。
- `docker-compose.bash` 仅注册带横线的独立命令 `docker-compose`，不改动
  `docker compose` 或其他 Docker 补全。服务名通过
  `docker-compose [已有全局参数] config --services` 获取，profile 通过
  `config --profiles` 获取，不查询 Docker daemon、不执行 `up` / `exec`。
  保留重复的 `-f`、`--env-file`、项目名/目录、profile 等全局参数；支持含空格
  的文件路径及 `--file=路径`、`-f路径`。`exec` / `run` 补全的是 **Compose 服务名**，
  不是容器 ID，输入服务名后不再补全容器内的命令。
  动态查询需要安装 `docker-compose` 和支持 `-k` 的 `timeout`，限时 2 秒，
  额外 1 秒后强制结束客户端；配置缺失/错误、缺少环境变量或版本不支持时静默返回。
  不读取标准输入作为配置，不对显式 URL 或 `-f -` 查询；本地配置仍由 Compose
  自己解析，包括它所引用的其他文件。不自行解析 YAML，不做变量或命令替换。
  静态候选兼顾常见 Compose V1 / V2 standalone，旧版本未必支持所有选项或 profile 查询。
- `nslookup` 不发起 DNS 查询；目前不补全交互式提示符中的命令。
- `ipset` 只执行只读查询，失败时静默返回，不提权、不修改集合；有 `timeout` 时每次限时 2 秒。
  使用命令行中输入的同一个二进制（如 `./ipset`）。支持常用完整子命令及 `n` / `x` / `e` / `w` 别名。
  - 集合名：`ipset list -name`。
  - 集合类型：解析 `ipset help` 的 "Supported set types"，跟随本机 ipset 版本；
    这是用户态工具支持的类型，内核缺少对应模块时 `create` 仍会失败。查询失败时用脚本内固定列表。
  - `create` 参数：解析 `ipset help <类型>` 中 create 一节，`family` 补全 `inet`/`inet6`，
    已写过的参数不再列出。查询失败时用脚本内固定的常用参数。
  - `add` 参数：先用 `ipset list -t <集合>` 读取集合的类型和创建参数，再从 `ipset help <类型>`
    取 add 一节。`timeout` / `packets`、`bytes` / `comment` / `skbmark` 等只在集合创建时带了
    `timeout` / `counters` / `comment` / `skbinfo` 时列出，因为否则 `ipset add` 会报错；
    `nomatch` 只给支持它的类型（如 `hash:net`）。`list:set` 的条目和 `before`/`after` 补全集合名。
    `list -t` 失败（通常是非 root）时退回到不区分类型的常用参数。
  - `del` / `test` 的条目：从 `ipset list <集合>` 的 Members 读取已有成员，按已输入前缀过滤，
    最多列出 1000 个（`_MINI_IPSET_MAX_MEMBERS`）。内核仍会输出整个集合，几十万条的集合按 Tab
    可能要等到 2 秒超时；`test` 常用于检查不在集合里的地址，这时只能手工输入。
  - 冒号：`hash:ip`、`2001:db8::1` 等含冒号的词按实际命令行（`COMP_LINE`）处理，兼容 Bash 默认
    在冒号处分词。
  - 不补全：新集合名、`add` 的新条目、数值参数、`comment` 内容、交互模式（`ipset -`）和任意缩写。
    `comment "含 空格"` 之后的位置可能按空格误判。
- `lvm.bash` 注册 `lvm` 和 43 个 `pv*`/`vg*`/`lv*` 命令；`completions/` 中的 `lvcreate.bash`、
  `vgs.bash` 等都是指向 `lvm.bash` 的软链接，按需加载器（自带的和官方 `bash-completion`）
  按命令名找文件，所以每个命令都需要一个文件名。复制安装时用 `cp -R`（默认保留软链接）。
  系统装有 `bash-completion` 时，用户目录中的这些文件优先于系统自带的 lvm 补全。
- 选项名、哪些选项带参数、`y|n` / `--type` / `--alloc` / `--units` 等可选值，在按 Tab 时从
  本机 `<命令> --longhelp`（失败时 `--help`）解析，跟随本机 LVM 版本；按 LVM 2.03 的帮助格式
  编写，在 2.03.38 上实测，过旧版本（2.02.169 之前的帮助格式）只有很少的选项候选。
  同一个短选项在不同命令中含义不同（如 `lvs -a` 不带参数、`lvcreate -a y`），因此按命令分别解析。
- PV/VG/LV 名称来自 `pvs`/`vgs`/`lvs --noheadings -o ...`，`lvs -o` 字段名来自 `lvs -o help`，
  都是只读报告命令，不激活、不修改卷；有 `timeout` 时限时 2 秒（额外 1 秒强制结束）。
  通常需要 root：普通用户查询失败时没有名称候选，只有选项候选。LV 写成 `VG/LV`，
  `lvrename VG` 之后补全该 VG 内的 LV 名。不列出 `-a` 才显示的内部 LV。
- `pvcreate`、`vgcreate`、`vgextend`、`vgimportclone`、`--devices` 的磁盘候选读取 `/sys/class/block`，
  排除：大小为 0 或只读的设备、`ram*`/`zram*`、已有分区的整盘、已被 device-mapper/LVM
  占用（`holders` 非空）的设备、LVM 自己的 LV，以及 `/proc/mounts`、`/proc/swaps` 中的设备；
  dm 设备显示为 `/dev/mapper/<名称>`。只是减少误选，不保证设备上没有数据：未挂载的文件系统、
  RAID 成员、尚未加入 VG 的 PV 仍会列出，执行前请用 `lsblk -f` / `blkid` 确认。
  输入含 `/` 的路径（如 `/dev/disk/by-id/`）时同时补全文件路径。
- 位置参数类型按命令写在脚本里（如 `vgextend VG 磁盘`、`vgreduce VG PV`、`lvextend LV PV`、
  `lvcreate -s` 后为源 LV、`-T` 后为 VG 或 `VG/thinpool`）；新卷名、大小、标签、`--select`
  表达式、`lvmconfig` 配置项不补全。`-L10G`、`-ay` 这类参数紧贴选项的写法能正确跳过，
  但不补全紧贴部分的值；命令行按空白分词。
- `tar` 支持 `-f`、`--file=路径`、`-C`、`--directory=目录` 等参数补全。
  不读取归档内容、不执行压缩程序；解包/列出时的成员名不从归档中查询，
  而是提供本地路径。常用无横线组合支持以 `f` 结尾（如 `xzvf`），不完整解析
  同时含多个带参数短选项的传统组合。
- `tmux` 子命令表和各子命令的选项来自 tmux 3.8 `list-commands`，固定写在脚本里：
  `list-commands` 在没有服务端时会临时启动一个，并在 socket 目录留下文件，
  所以不在按 Tab 时调用。其他版本的 tmux 新增或删除的子命令、选项可能不准确。
  会话、窗口、窗格、客户端、缓冲区、键表、选项名和 hook 名在按 Tab 时向**已运行的**
  服务端查询，只执行 `list-*`、`show-options`、`show-hooks`；没有服务端时这些候选为空，
  不会启动服务端。查询使用输入的同一个二进制（如 `./tmux`）及命令行中的 `-L`/`-S`；
  有支持 `-k` 的 `timeout` 时限时 2 秒。
  选项值只对开关型选项补全 `on`/`off`；`status`、`extended-keys` 等还接受其他取值，需手工输入。
  不支持 `-twork` 这种参数紧贴选项的写法，不补全按键名、格式串、`-f` 客户端标志；
  名称含空格的会话/窗口不做转义处理。
- `git.bash` 加载时先查找 git 自带的官方补全脚本（`/usr/share/bash-completion/completions/git`、
  `/usr/share/git-core/contrib/completion/git-completion.bash`、`/etc/bash_completion.d/git`），
  找到就直接用它：官方脚本跟随本机 git 版本、覆盖更全，且不依赖 `bash-completion` 包。
  这样即使系统装了 `bash-completion`，用户目录里的 `git.bash` 也不会把官方补全换成简化版。
  没有官方脚本时（如 Alpine 未装 `git-bash-completion`、最小化安装）才使用自带规则。
  设置 `MINI_GIT_OFFICIAL_COMPLETION=`（空值）可强制使用自带规则，也可设为空格分隔的其他脚本路径。
- 自带 git 规则只执行本地只读查询：`for-each-ref`、`remote`、`ls-files`、`diff --cached --name-only`、
  `stash list`、`config --get-regexp`/`--list`，以及 `<子命令> --git-completion-helper`
  （git 2.18+ 输出该版本实际支持的选项；旧版本报未知选项后退出，此时用脚本内的常用选项）。
  查询带 `GIT_OPTIONAL_LOCKS=0`，跟随命令行中的 `-C`、`--git-dir`、`--work-tree`，有 `timeout` 时限时 2 秒。
  **不访问远程仓库**：`fetch`/`pull`/`push` 的分支名来自本地 `refs/remotes/<远程>/`，
  远程新建、尚未 fetch 的分支不会出现（官方脚本会执行 `ls-remote`）。
- 自带 git 规则的文件候选：`add` 为已修改、已删除和未跟踪文件（未跟踪目录合并为 `目录/`），
  `restore`、`checkout --` 为已修改文件，`restore --staged`、`reset --` 为已暂存文件；
  均为相对当前目录的完整路径，只含当前目录及子目录中的文件，不在仓库中时退化为本地路径。
  不补全 `HEAD:路径` 中的路径、`git -c` 的配置值、`git log --format=` 等格式串和提交哈希；
  别名只补全名称，不按别名展开后的命令补全参数。命令行按空白分词、不解析引号；
  文件候选支持含空格的文件名。
- 这是常用运维场景的轻量规则，不是所有版本、子命令和语法的完整解析器。
  通常请使用分开的选项参数（如 `systemctl --type service`）；专门支持
  `nslookup -type=AAAA`、`grep --color=auto`、Docker 镜像标签和
  `lsof -s TCP:LISTEN` 等写法。
- 不解析 `sed`/`awk` 程序、复杂 `find -exec` 表达式、完整 nft 规则语言，
  不将 `xargs` 后的参数转发给其他命令的补全器；Docker Compose/Buildx
  仅提供部分子命令，不解析容器内命令或 Compose 文件。
- `grep`、`find`、`sed`、`xargs`、`tar` 以常见 GNU/Linux 版本为主，BusyBox、BSD
  或旧版本可能不支持所列部分选项；补全候选不代表本机一定支持该功能。

### 自测

测试只在源码仓库中，发布包不含 `tests/`。在源码仓库的项目根目录运行：

```bash
bash tests/completions.bash
```

测试会检查补全注册、脚本语法、常用参数、动态候选、带空格路径和禁止远程
Docker 查询。动态命令使用桩函数，不访问真实服务、防火墙或容器。
测试临时文件默认创建在 `/tmp/opencode`（需已存在），其他环境可指定
`TMPDIR` 为可写临时目录。

官方参考： [ipset 手册](https://ipset.netfilter.org/ipset.man.html)，
[git 官方补全脚本 git-completion.bash](https://github.com/git/git/blob/master/contrib/completion/git-completion.bash)，
[LVM 命令手册 lvm(8)](https://man7.org/linux/man-pages/man8/lvm.8.html)、[lvcreate(8)](https://man7.org/linux/man-pages/man8/lvcreate.8.html)、[lvs(8)](https://man7.org/linux/man-pages/man8/lvs.8.html)。

## 安装

推荐把目录内容复制到 Bash 官方约定的用户目录：

```bash
mkdir -p "$HOME/.local/share/bash-completion"
cp -R bash-completion-lite/. "$HOME/.local/share/bash-completion/"
```

在 `~/.bashrc` 中加入：

```bash
[ -r "$HOME/.local/share/bash-completion/init.bash" ] &&
    source "$HOME/.local/share/bash-completion/init.bash"
```

重新加载：

```bash
source ~/.bashrc
```

测试：

```bash
kill -9 <Tab><Tab>
```

## 添加自己的补全

每个命令一个文件，推荐使用 `<命令>.bash`：

```text
~/.local/share/bash-completion/completions/
├── kill.bash
├── kubectl.bash
└── authselect.bash
```

补全文件需要自己完成注册，例如：

```bash
_my_command_completion()
{
    local current="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=( $(compgen -W "start stop status restart" -- "$current") )
}

complete -F _my_command_completion my-command
```

命令自带的脚本也可以直接生成到这个目录：

```bash
kubectl completion bash > \
    "$HOME/.local/share/bash-completion/completions/kubectl.bash"
```

已有脚本可以复制并按命令名重命名：

```bash
cp /etc/bash_completion.d/authselect-completion.sh \
    "$HOME/.local/share/bash-completion/completions/authselect.bash"
```

## 使用独立目录

如果不想使用标准目录，可以保留整个项目目录，并在 `~/.bashrc` 中先设置：

```bash
export MINI_BASH_COMPLETION_ROOT="$HOME/.mini-bash-completion"
source "$MINI_BASH_COMPLETION_ROOT/init.bash"
```

检测到官方 `bash-completion` 时，如果它看不到这个自定义目录，入口会安全地预加载自定义规则，而不会替换官方 loader。

## 排查

确认完整的 `bash-completion` 是否已加载：

```bash
declare -p BASH_COMPLETION_VERSINFO 2>/dev/null
```

查看默认补全器：

```bash
complete -p -D
```

查看命令最终注册的规则：

```bash
complete -p kill
```

查看函数定义：

```bash
type _mini_kill_completion
```

如果补全文件是在当前 Shell 启动后新增的，并且命令已有旧规则：

```bash
complete -r kill
kill -9 <Tab><Tab>
```
