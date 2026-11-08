# file 5.48 纯静态版（内嵌 magic 数据库）

file 5.48（2026-06-07 发布，经 astron.com 下载页和 GitHub 标签 `FILE5_48` 核实为当前最新版本），
Alpine 3.22 + musl 从源码静态构建。支持 Linux x86_64 / aarch64，没有动态解释器和 NEEDED 依赖。

**单个文件即可使用**：编译后的 magic 数据库已经内嵌在二进制中，目标机不需要 `/usr/share/misc/magic`。
精简系统（如 CentOS 7、Ubuntu 16.04 的最小镜像）默认没有装 file，可以直接用这个版本。

## 为什么要内嵌 magic 数据库

file 判断文件类型靠的是 magic 数据库，二进制本身没有识别规则。上游默认按以下顺序找数据库：
`MAGIC` 环境变量 → `~/.magic.mgc` → 编译时写死的 `/usr/share/misc/magic`。
静态二进制拿到别的机器上会出现两种问题：

- 目标机没有数据库：什么都识别不了。
- 目标机有旧版数据库：编译后的 `.mgc` 格式与 file 版本绑定，会报版本不匹配；
  即便能读，识别结果也是旧版数据库的结果，不是 5.48 的。

所以构建时把同一次构建生成的 `magic.mgc` 用 `.incbin` 链接进二进制，运行时用上游接口
`magic_load_buffers` 加载。补丁见 `embed-magic.patch`，只改 `src/file.c`，未定义 `FILE_EMBED_MAGIC`
时与上游完全相同。

| 情况 | 使用的数据库 |
| --- | --- |
| 默认（没有 `-m`，也没有 `MAGIC`） | 内嵌数据库，`file --version` 显示 `magic file embedded` |
| `-m 文件` 或 `MAGIC=文件` | 指定的文件（与上游相同）；文件无效时报错，不会回退到内嵌数据库 |
| `-l`、`-c`、`-C` | 这三个操作上游按路径处理，**不用内嵌数据库**；不加 `-m` 时读系统 `/usr/share/misc/magic` |

**与上游的差别**：默认不读 `~/.magic`、`~/.magic.mgc`。需要个人规则时用
`-m ~/.magic:` 或 `MAGIC` 指定（此时同样不包含内嵌数据库）。

## 使用

```sh
./file /usr/bin/ls a.tar.gz data.bin
./file -b --mime-type img.png        # image/png
./file -i text.txt                   # text/plain; charset=us-ascii
./file -z backup.tar.xz              # 查看压缩包内部的类型
./file -s /dev/sda1                  # 读块设备内容（需要权限）
./file -L link                       # 跟随符号链接
./file --version
```

## 功能取舍

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| 内置解压 `-z`：gzip、zlib、bzip2、xz/lzma、zstd、lzip | 启用 | zlib/bzip2/xz/zstd 用 Alpine 静态库；lzlib 1.16 从源码构建（Alpine 只有动态库） |
| `-z` 外部解压：.Z（compress）、lz4、lrzip、frozen 等 | 调用外部命令 | 没有内置库，运行时需要 PATH 中有 `gzip`、`lz4`、`lrzip` 等命令；没有时只显示外层压缩格式（已验证 lz4） |
| liblrzip | 不启用 | Alpine 的 lrzip 包不提供 liblrzip；`.lrz` 照常识别，查看内部需外部 `lrzip` 命令 |
| seccomp、Landlock 沙箱 | **不启用** | 见下文 |
| ELF、ELF core 解析 | 启用（上游默认） | |

### 为什么不启用 seccomp 和 Landlock 沙箱

这是功能与安全加固之间的取舍，选择与 Fedora、Debian、Alpine 一致（这三者的 file 都没有启用 seccomp）：

- 上游在 seccomp 沙箱开启时（默认开启）会设置 `MAGIC_NO_COMPRESS_FORK`，此时 `-z` 对**所有**压缩格式
  （包括内置解压）都报 `Fork is required to uncompress, but disabled`，必须加 `-S` 才能用。已在构建中实测。
- 5.48 新增的 Landlock 会禁止执行外部程序，外部解压命令在 5.13 及以上内核上会被拦截；
  而且未编译 seccomp 时，`-S` 不会关闭 Landlock。

影响：分析不可信文件时，没有系统调用和文件系统层面的额外限制。`-S` 参数仍可接受，但没有作用。

## 运行依赖与行为

- 不需要任何数据文件、共享库或配置文件。
- `-z` 查看 .Z、lz4、lrzip 等格式内部时需要对应外部命令，见上表。
- 读取管道输入（`cat x | file -`）与上游相同。
- `-p`（保留访问时间）、`-s`（读设备）需要相应权限。
- 发布到 `static_tools/<架构>/file`。解压到 `/usr/local/bin` 后，按 PATH 顺序会优先于系统的 `/usr/bin/file`。
  识别结果按 5.48 的数据库给出，可能比系统自带的版本更详细，个别描述文字会不同。

## 构建和产物

需要 Docker、默认 buildx，构建需要联网。默认只构建当前主机架构：

```sh
./build.sh amd64 --progress plain       # 本机 x86_64
./build.sh aarch64 --progress plain     # 在 192.168.182.150 原生执行
```

脚本不创建、修改或切换 builder，不安装模拟器。共享目录下不要在两台机器上并发构建同一架构。

构建分两步：第一次 `make` 生成 `src/file` 和 `magic/magic.mgc`（由刚编译的 file 生成）；
第二次只重新编译 `file.c`，把 magic.mgc 内嵌进去，并用 `-all-static` 完全静态链接。
configure 会检查 5 个压缩库都已启用（`*SUPPORT` 宏），并确认 seccomp、Landlock 没有被编译进去。

```text
dist/
├── x86_64/       # file、file.1、magic.5、COPYING.file、COPYING.lzlib、SHA256SUMS
├── aarch64/
├── file-5.48-linux-x86_64-static.tar.gz
└── file-5.48-linux-aarch64-static.tar.gz
```

| 文件 | x86_64 | aarch64 | 说明 |
| --- | --- | --- | --- |
| `file` | 约 11.0 MB | 约 10.9 MB | 大部分是内嵌的 magic 数据库，压缩包约 0.9 MB |
| `file.1`、`magic.5` | | | 手册页，`man ./file.1`；`magic.5` 为第 5 节（`--enable-fsect-man5`） |
| `COPYING.file`、`COPYING.lzlib` | | | 均为 BSD 风格许可 |

### 固定版本与校验

| 组件 | 来源 | SHA-256 | 校验依据 |
| --- | --- | --- | --- |
| file-5.48.tar.gz | astron.com | `ed146568…1283` | 作者 Christos Zoulas 的 GPG 签名验证通过（公钥已过期，签名有效） |
| lzlib-1.16.tar.gz | download.savannah.nongnu.org | `203228de…b038` | 作者 Antonio Diaz Diaz 的 GPG 签名验证通过 |

完整哈希见 Dockerfile。zlib、bzip2、xz、zstd 静态库和 musl 随 Alpine 3.22 分支仓库更新，未锁定版本，
本次构建使用 zlib 1.3.2、musl 1.2.5。升级时同步修改 Dockerfile 中的版本和哈希，并确认
`embed-magic.patch` 仍能应用。

## 验证

构建阶段（x86_64 在本机原生，aarch64 在 192.168.182.150 原生）必须通过以下检查才导出：

1. `readelf -h` 架构正确；`readelf -l` 无 `INTERP`，`readelf -d` 无 `NEEDED`；`--version` 为 `file-5.48`，
   显示 `magic file embedded`，不含 seccomp、Landlock。
2. 上游测试套件 `make -C tests check`：84 个样例全部通过（使用 `magic/magic.mgc`，测试识别规则和 libmagic）。
3. 删除构建容器中 Alpine 自带的 magic 数据库，并清空环境变量后运行 `test/smoke-test.sh`：
   - 识别自身 ELF、shell 脚本、文本、PNG（含尺寸）、zip、PDF、JSON、SQLite、tar。
   - `--mime-type`、`-i`、`--extension`。
   - `-z`/`-Z` 内置解压 gzip、bzip2、xz、zstd、lzip；`-z` 调用外部 lz4 命令，PATH 中没有时退回只显示外层格式。
   - 管道输入、符号链接（默认不跟随 / `-L`）、`-k`、`-f`、`-s`。
   - 16 个样例分别用内嵌数据库和构建生成的 `magic.mgc` 识别，结果一致。
   - `-m`、`MAGIC` 覆盖内嵌数据库；`MAGIC` 指向不存在的文件时报错；`-C` 编译、`-c` 检查自定义规则。

在老发行版上验证（`test/old-system-test.sh`，x86_64、aarch64 分别在对应主机原生运行，容器断网）：
CentOS 7、Ubuntu 16.04 最小镜像中都没有 file，静态版可直接运行，内嵌数据库生效，JSON 识别、`-z` 正常。

**未验证**：真实的老系统物理机或虚拟机（以上测试使用容器，内核是宿主机的）；
.Z、lrzip、frozen 等外部解压格式（只测了 lz4）。

## Reference Documentation

- [file 官方主页](https://darwinsys.com/file/)（本次检查时返回 502，未能打开）
- [file 下载页](https://astron.com/pub/file/)
- [file GitHub 镜像](https://github.com/file/file)
- [file 5.48 ChangeLog](https://github.com/file/file/blob/FILE5_48/ChangeLog)
- [file(1) 手册页](https://man7.org/linux/man-pages/man1/file.1.html)
- [magic(5) 手册页源码（5.48）](https://github.com/file/file/blob/FILE5_48/doc/magic.man)
- [libmagic(3)：magic_load_buffers](https://man7.org/linux/man-pages/man3/libmagic.3.html)
- [lzlib 主页](https://www.nongnu.org/lzip/lzlib.html)
