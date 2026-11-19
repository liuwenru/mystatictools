# iotop-c 1.33 纯静态构建

基于 Alpine 3.22 + musl，静态链接宽字符 ncurses 6.6。只需对应架构的 `iotop` 文件即可运行，不需要 Python、glibc、共享库或联网。未修改上游采集逻辑和功能选项。

## 构建和使用

使用默认 buildx；默认构建当前主机架构，ARM 建议在原生 aarch64 主机构建：

```sh
./build.sh amd64
./build.sh aarch64
```

二进制位于 `dist/x86_64/iotop` 或 `dist/aarch64/iotop`。同级 `dist/` 下的 `iotop-1.33-linux-<架构>-static.tar.gz` 包含二进制、man 手册、许可证和 `SHA256SUMS`。构建时联网获取 Alpine 软件包和上游源码；iotop 和 ncurses 源码按版本及 SHA-256 固定，Alpine 软件包随 3.22 仓库更新。

```sh
./iotop --version
sudo ./iotop -oP             # 交互：只显示有 I/O 的进程，按 q 退出
sudo ./iotop -b -P -n 5 -d 1 # 批处理：按进程采样 5 次
sudo ./iotop -b -P -a -p PID # 观察指定进程的累计 I/O
```

保留上游的批处理、进程和线程视图、读写速率、累计 I/O、等待时间、排序、过滤及 I/O 优先级操作。优先级操作能否生效仍取决于权限、内核和 I/O 调度器；`Ctrl-T` 只适用于提供 `kernel.task_delayacct` 的内核。用户名依赖 musl 能读取的本地用户数据库，不能假定支持目标机的 glibc NSS 插件（例如 LDAP/SSSD）。

## CentOS 7 和运行条件

- 运行时需要 `/proc`、Linux `TASKSTATS` 和 `/proc/vmstat`；内核配置关注 `CONFIG_TASKSTATS`、`CONFIG_TASK_DELAY_ACCT`、`CONFIG_TASK_XACCT`、`CONFIG_TASK_IO_ACCOUNTING`、`CONFIG_VM_EVENT_COUNTERS`。
- 建议用宿主机上的 `sudo`。容器内 UID 0 并不保证可以查询 `TASKSTATS`；容器权限和命名空间仍会限制访问。不要为绕过报错给普通用户长期授予 `CAP_NET_ADMIN`。
- `/proc/PID/io` 可用于交叉检查，但本工具没有用它替代 `TASKSTATS` 的后备路径。只有总计在变化或进程列表能显示，并不能证明进程级统计可用。
- EL7 的 3.10 内核通常没有 `kernel.task_delayacct`；不存在该 sysctl 不代表缺少统计。上游 3.10 在启用对应内核配置后默认采集延迟，除非启动参数包含 `nodelayacct`。5.14 及后续内核通常可通过该 sysctl 运行时启用；启用后只有新启动任务的数据可用于延迟统计。不要把等待时间为零解释成没有磁盘读写。
- 系统 terminfo 可正常使用；目标系统缺少时回退到内嵌的 `ansi`、`linux`、`vt100`、`vt102`、`vt220`、`xterm`、`xterm-256color`、`xterm-direct`、`screen`、`screen-256color`、`tmux`、`tmux-256color`、`rxvt`、`rxvt-256color`、`alacritty`、`foot`、`xterm-kitty`。其他终端可通过 `TERMINFO` 指定真实的终端定义。交互模式需要终端，UTF-8 环境下可以使用 Unicode 绘图。

## 验证

构建会检查 ELF 架构和版本，确认没有 `PT_INTERP` 或 `DT_NEEDED`，在无网络、无系统 terminfo 时检查内嵌终端定义，并执行上游配置测试。在 `scratch` 阶段另外验证二进制不依赖运行镜像中的 shell 或共享库即可启动。

```sh
# 原生 Linux，第二个参数必须是磁盘文件系统上的可写目录
sudo ./test/batch-io.sh ./dist/x86_64/iotop /var/tmp
# x86_64：官方 CentOS 7.9 内核 + 最小 initramfs，不启动宿主上的服务
sh ./test/centos7.sh ./dist/x86_64/iotop /path/to/static-busybox
```

CentOS 7 测试使用 `3.10.0-1160.el7.x86_64` 内核、无网卡的 QEMU 客机和临时虚拟磁盘。需要 `curl`、`rpm2cpio`、`cpio`、`xz`、`mkfs.ext4`、QEMU 和静态 x86_64 BusyBox，不安装到目标机。

本次 x86_64 和 aarch64 产物均在各自的原生主机构建，并通过进程写入测试。ARM 宿主的延迟统计已关闭，测试没有修改该设置，只验证磁盘字节数。

x86_64 产物另在上述 EL7 内核上通过验证：测试进程的累计写入达到 384 KiB，与 `/proc/PID/io` 一致，并采到了非零 I/O 等待时间。无系统 terminfo 时，`xterm-256color`、`tmux-256color` 和 `xterm-kitty` 均能显示交互界面并按 `q` 退出。未验证其他 EL7 补丁版本、生产机定制内核或 EL7 aarch64。

## Reference Documentation

- [iotop-c 1.33 发布与源码](https://github.com/Tomas-M/iotop/releases/tag/v1.33)
- [iotop-c 1.33 手册](https://github.com/Tomas-M/iotop/blob/v1.33/iotop.8)
- [ncurses 构建与 fallback terminfo](https://invisible-island.net/ncurses/INSTALL.html)
- [Linux 3.10 延迟统计](https://github.com/torvalds/linux/blob/v3.10/Documentation/accounting/delay-accounting.txt)
- [CentOS 7.9 x86_64 官方归档](https://vault.centos.org/7.9.2009/os/x86_64/)
