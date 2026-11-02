# tree 2.3.2 纯静态版

基于 Steve Baker 官方 tree 2.3.2（2026-03-16 发布，经官方下载页和 GitLab 标签核实为当前最新版本），
使用 Alpine 3.22 + musl 构建 Linux x86_64 / aarch64 的 `tree`。
tree 只依赖 libc，musl 静态链接后运行时不需要共享库或动态加载器。

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
├── x86_64/                # tree、tree.1、global_info、LICENSE、SHA256SUMS
├── aarch64/
├── tree-2.3.2-linux-x86_64-static.tar.gz
└── tree-2.3.2-linux-aarch64-static.tar.gz
```

运行包内容：

- `tree`：静态二进制（x86_64 约 135 KB，aarch64 约 196 KB）。
- `tree.1`：官方手册页，`man ./tree.1` 查看。
- `global_info`：官方 `--info` 示例文件，见下文。
- `LICENSE`：GPL-2.0。

固定源码 `tree-2.3.2.tgz`（来自官方下载页），SHA-256：

```text
6b941dd6cbecfb4d3250700e4d08d8e0c251488981dd4868b90d744234300e21
```

官方没有发布校验值。该哈希是首次下载时计算的；解压后与 GitLab `2.3.2` 标签源码逐文件比较，内容完全一致。
GitLab 自动生成的归档哈希不同，不能互换。

Alpine 依赖随 3.22 分支仓库更新，未锁定版本。本次构建实际使用：
gcc 14.2.0、musl 1.2.5、binutils 2.44。
升级 tree 需同时修改 Dockerfile 中的版本和 SHA-256、`build.sh` 中的版本、
`test/smoke-test.py` 中的版本断言。

## 编译方式

直接使用官方 Makefile 的 Linux 默认配置，只通过环境变量传入 `CFLAGS=-O2 LDFLAGS=-static`，
未修改上游源码，没有关闭任何功能。tree 没有 configure 和可选依赖：

- `-J`/`-X`/`-H`（JSON、XML、HTML 输出）是内置代码，不需要外部库。
- `--acl`、`--selinux` 直接调用 `listxattr`/`getxattr` 系统调用，
  不需要 libacl、libselinux，静态版功能和发行版 tree 相同。
- 颜色输出是写死的 ANSI 转义序列，不读 terminfo。

## 使用

```sh
./tree -L 2 /etc
./tree -a -p -u -g -h -D /var/log    # 权限、属主、属组、大小、时间
./tree --du -h -d /data               # 目录累计大小
./tree -P '*.conf' --prune /etc       # 只显示匹配文件及其所在目录
./tree -I 'node_modules|.git' .
./tree --gitignore .
./tree -J /srv > tree.json            # 也有 -X（XML）、-H base（HTML）
./tree -C | less -R                   # 管道中强制颜色
./tree --acl --selinux /path
```

## 运行依赖与行为

纯静态不等于没有运行时依赖：

- **locale**：musl 只支持 UTF-8，没有 locale 数据文件。不设置任何 `LANG`/`LC_*` 时，
  musl 默认就是 C.UTF-8，因此默认输出 UTF-8 制表符和中文文件名，不需要 `/usr/lib/locale`。
  `LC_ALL=C` 或 `LANG=C` 时改用 ASCII 线条（`|--`）。
  GBK、GB18030 等非 UTF-8 locale 不生效，仍按 UTF-8 处理。
- **排序（与 glibc 版唯一的差异）**：musl 的 `strcoll` 按字节比较，没有语言排序规则。
  `en_US.UTF-8`、`zh_CN.UTF-8` 下 glibc 版按语言排序规则（忽略点号、大小写等），静态版仍按字节序排
  （点文件在前，大写在小写前，中文在 ASCII 之后），效果等同 glibc 版的 `LC_ALL=C tree`。
  C/C.UTF-8 下两者输出逐字节相同（构建时对比过）。需要固定顺序时可用 `-v`（版本排序）或 `--sort`。
- **`-u`/`-g` 用户名、组名**：只读 `/etc/passwd`、`/etc/group`，不走 NSS，
  LDAP/SSSD 用户显示为数字 UID/GID。
- **颜色**：需要终端且设置 `TERM` 变量（任何值都行）；`TERM` 未设置时即使 `-C` 也不着色。
  使用 `LS_COLORS` 或 `TREE_COLORS`；未设置但有 `CLICOLOR`/`CLICOLOR_FORCE` 时用内置配色。
  `NO_COLOR` 或 `-n` 关闭颜色，`-C` 优先于 `-n`。
- **`-D` 时间**：时区读 `TZ` 和 `/etc/localtime`，都没有时显示 UTC。
- **`--info`**：读取各目录的 `.info` 文件和 `/usr/share/finfo/global_info`（不存在则忽略）。
  运行包中的 `global_info` 是官方示例，需要时复制到该路径或用 `--infofile=./global_info`。
- **`--acl`/`--selinux`**：取决于文件系统是否保存对应 xattr；没有 SELinux 标签的文件显示为空 `[]`，
  命令行起始目录没有标签时显示 `(null)`（上游行为，glibc 版相同）。
- 不需要 shell、证书、插件、终端定义或其他辅助程序。

## 已知上游问题（与静态编译无关，glibc 版相同）

- `-H` 生成的链接在基础路径和目录之间不自动加 `/`（`-H .` 得到 `.t/a`），需要写成 `-H ./`。
- `-H` 对非 ASCII 文件名做 URL 编码时有符号扩展问题，中文文件名链接变成 `%FFFFFFE4...`。
- `-l` 跟随符号链接时，目标若已访问过（包括指向树内目录的链接）也标为 `[recursive, not followed]`。
- 统计行的目录数包含起始目录本身和指向目录的符号链接（`d/a` 显示 2 directories）。

## 验证

构建阶段必须通过下列检查才导出：

1. `file`、`readelf -h` 检查架构；`readelf -l` 无 `INTERP`，`readelf -d` 无 `NEEDED`。
2. `--version` 为 2.3.2。
3. `test/smoke-test.py` 在只含二进制和最小 `/etc/passwd`、`/etc/group` 的 chroot 中运行
   （无共享库、shell、locale 数据）：默认输出逐字比对、无 locale 环境变量时 UTF-8 线条、
   `LC_ALL=C` ASCII 线条、`-a -L -d -f -i -F`、排序选项、`--condense`、`--compress`、
   `-P/-I/--prune/--ignore-case/--gitignore`、`-p -u -g` 名称与未知 ID、`-s -h --si --du`、
   `-D --timefmt` + `TZ`、`--inodes --device`、`-l` 及循环链接、JSON/XML 解析、HTML、
   `-o`、`--fromfile`、`--info`、颜色相关环境变量、UTF-8 文件名、不可打印字符转义及
   `-q -N`、不存在目录的报错和退出码、`--acl`、`--selinux`。
   `--selinux` 标签在容器内可能不允许写入，此时只验证能运行，标记为 SKIP。

上游源码没有自带测试套件。测试主机和结果见 `test/VALIDATION.md`。

## Reference Documentation

- [官方主页与下载页](https://oldmanprogrammer.net/source.php?dir=projects/tree)
- [官方源码 tree-2.3.2.tgz](https://oldmanprogrammer.net/tar/tree/tree-2.3.2.tgz)
- [GitLab 仓库（官方）](https://gitlab.com/OldManProgrammer/unix-tree)
- [2.3.2 CHANGES](https://gitlab.com/OldManProgrammer/unix-tree/-/blob/2.3.2/CHANGES)
- [手册页 tree.1](https://gitlab.com/OldManProgrammer/unix-tree/-/blob/2.3.2/doc/tree.1)
- [许可证 GPL-2.0](https://gitlab.com/OldManProgrammer/unix-tree/-/blob/2.3.2/LICENSE)
- [musl 与 glibc 功能差异（locale、排序）](https://wiki.musl-libc.org/functional-differences-from-glibc.html)
