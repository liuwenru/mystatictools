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
| `nft` | 常用操作、对象、协议族、已有表/链/集合、部分规则关键字 |
| `scp` | 常用选项、SSH 配置中的 Host 别名、本地路径 |
| `docker` | 常用子命令/选项、本机容器/镜像/网络/卷名，`cp` 两端的本地/容器路径，部分二级子命令 |
| `docker-compose` | 独立命令的常用子命令/选项、Compose/环境文件路径、项目目录、服务名和 profile |
| `lsof` | 常用选项、PID、用户、协议/端口示例、TCP 状态、路径 |
| `sed` | 常用 GNU 选项、脚本文件和输入文件路径 |
| `awk` | 通用短选项 `-F`、`-v`、`-f`、`-W`，文件路径 |
| `xargs` | 常用选项、命令名、`-a` 文件及命令后的本地路径 |
| `tar` | 常用选项、`-xzvf` / `xzvf` 组合、归档/输入文件路径、`-C` 目录、格式和引用风格 |

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
- `docker exec` 和 `docker container exec` 补全运行中容器的短 CONTAINER ID
  （来自 `docker ps --format '{{.ID}}'`），支持 `-it`、`--user root` 等选项后的
  ID 补全；其他原有按容器名称补全的子命令保持不变。
- `docker cp`（包括 `docker container cp`）支持源端和目标端的路径补全：
  未输入冒号时提供本地路径及运行中容器的短 ID（带 `:`）；输入 `ID:/路径`
  后列出容器内目录，也允许手动输入容器名称。目录候选带 `/`，支持隐藏文件、
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
- `tar` 支持 `-f`、`--file=路径`、`-C`、`--directory=目录` 等参数补全。
  不读取归档内容、不执行压缩程序；解包/列出时的成员名不从归档中查询，
  而是提供本地路径。常用无横线组合支持以 `f` 结尾（如 `xzvf`），不完整解析
  同时含多个带参数短选项的传统组合。
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

在项目根目录运行：

```bash
bash tests/completions.bash
```

测试会检查补全注册、脚本语法、常用参数、动态候选、带空格路径和禁止远程
Docker 查询。动态命令使用桩函数，不访问真实服务、防火墙或容器。
测试临时文件默认创建在 `/tmp/opencode`（需已存在），其他环境可指定
`TMPDIR` 为可写临时目录。

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
