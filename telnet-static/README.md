# Telnet 2.8 纯静态版

GNU Inetutils 2.8 的 **telnet 客户端**，用 Alpine 3.22 + musl 构建 x86_64 和 aarch64。
版本来自 GNU 官方发布目录（2026-11-17 核对）。不包含 telnetd 服务端。

## 构建与产物

```sh
./build.sh                         # 当前主机架构
./build.sh amd64 --progress plain
./build.sh aarch64 --progress plain
```

只用默认 buildx，不安装模拟器、不修改 builder。x86_64 在本机原生构建，aarch64 在
`192.168.182.150` 的同路径共享仓库原生构建；不要同时导出同一架构。
构建需联网下载源码和 Alpine 包；`--build-arg JOBS=8` 可调整并行编译数。

产物：

- `dist/x86_64/telnet`、`dist/aarch64/telnet`：单个可执行文件。
- `dist/telnet-2.8-linux-<架构>-static.tar.gz`：程序、手册、许可证、`BUILD-INFO`、`SHA256SUMS`。
- 构建和测试记录在 `BUILD-INFO`、下文“验证”中。测试代码只在 `test/`，不放进运行包。

```sh
./telnet 192.0.2.10                  # 默认 TCP 23
./telnet -4 192.0.2.10 2323
./telnet -6 ::1 2323
./telnet -8 -l operator host 23      # 8 位收发，协商用户名
./telnet -c host 23                  # 不读 ~/.telnetrc
./telnet -n session.trace host 23    # 协议跟踪
```

连接后按 `Ctrl+]` 进入命令模式，`?` 看帮助；支持 `open`、`close`、`quit`、`status`、
`mode`、`send`、`set`、`unset`、`toggle`、`environ`、`auth`、`encrypt` 等上游命令。
GNU Telnet 对自定义端口默认不主动发起 Telnet 协商；需要主动协商时使用 `./telnet -- host -2323`。

## 保留的功能与取舍

- 保留 IPv4/IPv6、本地地址绑定、8 位二进制传输、转义命令、`.telnetrc`、跟踪、rlogin 风格界面。
- 保留终端类型、窗口大小、ECHO、SGA、LINEMODE/SLC 和环境变量等上游协议选项。
- 启用 GNU Libidn，支持上游 IDNA2003 域名转换；没有伪装成 IDNA2008 支持。
- 静态编入 **Shishi 1.0.3**，保留 Kerberos V5 单向/双向认证、`-k`、`-X`、`auth`，
  以及 `-x`、`encrypt` 和上游 DES_CFB64/DES_OFB64 流加密。没有 Kerberos IV，也不增加上游不存在的 TLS。
  Shishi 的密码算法保持默认启用（DES、3DES、AES、ARCFOUR 等），不为体积裁剪。
- 按本任务确认关闭 **Shishi 到 KDC 的非标准 STARTTLS 扩展**，不影响 telnet 的 `-x` 流加密。
  普通 Kerberos KDC 连接仍保留；依赖此扩展的 KDC 不能直接使用这一构建，可通过现有 VPN 访问标准 KDC。
- Shishi 不构建 PAM 模块；客户端不使用 PAM。其他 Inetutils 客户端和服务端不构建。

`-x` 是“尽可能加密”的上游行为，并不保证连接强制加密；应在命令模式 `encrypt status` 确认。
流加密只有上游的旧式 DES 方案，不能把它当成现代安全传输；普通 Telnet 会明文传送登录信息和数据。

## 离线运行依赖

**普通连接只需这个可执行文件和内核 TCP/IP、终端/PTY**，不需要共享库、动态加载器或辅助程序。

- ncurses 6.6 静态编入常用终端定义：`ansi`、`dumb`、`linux`、`vt100/102/220`、
  `xterm`/`xterm-256color`/`xterm-direct`、`screen`/`screen-256color`、`tmux`/`tmux-256color`、
  `rxvt`/`rxvt-256color`、`alacritty`/`alacritty-direct`、`foot`/`foot-direct`、`xterm-kitty`、`xterm-ghostty`。
  后两项使用 ncurses 中对应终端的真实定义，只补实际 TERM 名称。仍支持读取系统 terminfo。
  未知 TERM 按上游回退为报告原名称，不冒充其他终端；TERM 超过 40 字符时上游报告 UNKNOWN。
- 本地补丁 `patches/prompt-flush.patch`：读取命令前显式刷新 stdout，修复 musl 环境中
  `telnet> ` 提示符一直缓冲、不显示的问题；初始提示符、交互式 `open` 的 `(to)` 提示符和 `Ctrl+]` 后均测试。
- 本地补丁 `patches/ncurses-tgetent.patch`：上游检测到 ncurses 后漏定义 `HAVE_TGETENT`，导致
  终端定义查询未编入。补全 ncurses 分支的宏和头文件选择，同时修改 m4 和生成的 configure。
- 本地补丁 `patches/default-port.patch`：`/etc/services` 没有 telnet/tcp 时默认端口回退为 23；
  有该记录时保持系统端口映射。显式指定数字端口不依赖 `/etc/services`，其他服务名仍需要相应记录。
- 域名解析使用 musl 的 `/etc/hosts`、`/etc/resolv.conf`，不使用 glibc NSS、LDAP/SSSD 或 mDNS。
  极简环境建议写数字 IP；`localhost` 也需要 hosts 或 DNS。
- `-a` 自动选用户名涉及系统用户信息，明确用户名可用 `-l 用户名`；`-l` 只协商用户名，不自动填写密码。
- `.telnetrc` 在 `$HOME` 下；跟踪文件和用户配置需要对应目录可写。
- `!` 本地 shell 命令需要 `$SHELL` 或 `/bin/sh`，并需要对应外部命令。这些不随包内置。
- `-d` 的 `SO_DEBUG` 可能需要额外权限，取决于目标内核；普通连接不需 root。

### Kerberos 配置

静态编入认证库不意味着不需要站点配置。Shishi 读取 `/etc/shishi/shishi.conf`，
用户配置默认 `$HOME/.shishi/shishi.conf`，票据文件默认 `$HOME/.shishi/tickets`；
可用 `SHISHI_HOME` 指向独立目录（配置文件与票据放在其中）。使用前按站点配置 realm、KDC、
主机名和用户身份，保持时钟同步并确保 KDC 可达或已有合适票据。
Shishi 的票据存储与 MIT Kerberos 的 `KRB5CCNAME` 不等同，不能假定系统 `kinit` 的缓存可直接使用。
Kerberos 密码运算还需要系统随机数源（现代 Linux 的 getrandom，或相应随机设备）。
实际 Kerberos 登录和加密还要求服务端支持相应 Telnet 扩展。本次没有连接用户的 KDC 或线上设备。

## 固定版本与许可证

| 源码 | 版本 | SHA-256 |
| --- | --- | --- |
| Inetutils | 2.8 | `57b3cf4f77555992881e5ba2a09a63b05aa2c56342a60ed4305b5f45938390b5` |
| Shishi | 1.0.3 | `95798ffd12dd01a4f88e0311ee03ca4a26e5cb4e5e9059a40e4fc4d9f2917e92` |
| Libtasn1 | 4.21.0 | `1d8a444a223cc5464240777346e125de51d8e6abf0b8bac742ac84609167dc87` |
| ncurses | 6.6 | `355b4cbbed880b0381a04c46617b7656e362585d52e9cf84a67e2009b749ff11` |

上述源码下载固定版本并验证哈希；Libgcrypt、Libgpg-error、Libidn 用 Alpine 3.22 静态包，
随该分支仓库更新，实际版本见包内 `BUILD-INFO`。升级静态库必须重新构建二进制。
许可证和依赖版权信息随包分发，文本来源见 `licenses/README.md`。Inetutils/Shishi 使用 GPLv3+；
对外分发还应按许可证提供对应源码及构建材料，构建入口为本目录的 Dockerfile 和补丁。

## 验证

构建必须通过 ELF 架构、无 INTERP、无 NEEDED、版本检查及 `test/smoke-test.py` 才能导出。
Libtasn1 和 Shishi 先运行各自上游 `make check`。

2026-11-18 完成：x86_64 在本机、aarch64 在 `192.168.182.150` 原生构建和测试，
两者均通过上述 ELF 检查、上游测试和 13 组离线交互测试；未使用模拟器。
程序约 2.3 MiB（x86_64）/ 2.1 MiB（aarch64），压缩包各约 1.1 MiB。

测试使用独立 socket、临时 chroot 和真实 PTY，在没有共享库、终端数据库、shell、`/etc`、`/dev` 的环境中，
检查 IPv4/IPv6 双向收发、TTYPE、NAWS、ECHO/SGA、BINARY、IAC 转义、`Ctrl+]`/status/quit、
认证和加密命令、未知终端回退及无 services 文件的默认 23 端口。
测试不启动登录服务或使用真实账号。

尚未端到端验证：真实 KDC 的 Kerberos 登录/加密、各型号设备的 LINEMODE/SLC 和环境变量实现、
真实离线目标机器的内核与网络策略。编译启用不等于这些场景已经验证。

## Reference Documentation

- [GNU Inetutils 官方发布目录](https://ftp.gnu.org/gnu/inetutils/)
- [GNU Inetutils 手册](https://www.gnu.org/software/inetutils/manual/html_node/index.html)
- [Telnet 用法](https://www.gnu.org/software/inetutils/manual/html_node/telnet-invocation.html)
- [GNU Shishi 项目](https://www.gnu.org/software/shishi/)
- [Shishi 手册](https://www.gnu.org/software/shishi/manual/)
- [ncurses](https://invisible-island.net/ncurses/)

发布脚本 `pushfdoc.sh` 仅在明确要求发布时运行，本任务不执行发布，也不执行 git commit/push。
