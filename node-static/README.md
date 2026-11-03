# Node.js 26.13.0 纯静态版

Node.js **v26.13.0**（LTS "Lithium"，2026-10-28 发布）在 Alpine 3.23 + musl 上用官方
`configure --fully-static` 编译，适用于 Linux x86_64 和 aarch64。`bin/node` 是静态 ELF，
没有动态解释器，也没有 NEEDED。目标机不需要 glibc、musl、libstdc++、OpenSSL 或 ICU。

用途：在离线机器上运行纯 JS 写的工具，例如 `yaml-language-server`、
`vscode-json-language-server`、`bash-language-server` 这类语言服务器。
以后不涉及 Node 的工具，不要改这个目录。

## 为什么自己编

| 来源 | 链接方式 | 结论 |
| --- | --- | --- |
| nodejs.org 官方 `linux-x64/arm64` | 动态链接 glibc | 老系统和 musl 系统用不了 |
| unofficial-builds `linux-x64-musl`、`linux-arm64-musl` | 动态链接 musl，NEEDED 有 `libstdc++`、`libgcc_s` | glibc 系统上会报 `not found` |
| bun `linux-x64-musl` | 动态链接 musl 和 `libstdc++` | 同上，而且不是 Node 本身 |

官方和非官方都**没有发布纯静态的 Node**，所以照 unofficial-builds 的
[`recipes/musl`](https://github.com/nodejs/unofficial-builds/tree/main/recipes/musl) 自己编。
做法相同（Alpine 3.23 原生编译，用 Alpine 的 `rust`/`cargo`），只多加了 `--fully-static`。
aarch64 在原生 ARM 主机上按同样方式编译，不用 unofficial-builds 的 `arm64-musl` 交叉编译配方。

## 构建选项

```
./configure --prefix=/ --dest-cpu=<x64|arm64> --fully-static \
  --with-intl=full-icu --v8-enable-temporal-support
make && make install DESTDIR=... PORTABLE=1
```

- `--fully-static`：链接时加 `-static`。在 Alpine 上生成 `static-pie`。
- `--with-intl=full-icu`：和官方发布版一样，带完整的 ICU 数据。数据已在源码包里，编译时不用下载。
  中文日期、各地时区换算不依赖系统的 `/usr/share/zoneinfo`。
- `--v8-enable-temporal-support`：Node 26 的 `Temporal` 由 Rust 的 temporal_rs 提供。
  找不到 cargo 时，configure 会**悄悄关掉** Temporal。加这个选项后，没有 cargo 会直接报错。
  Rust crate 已随源码 vendor（`deps/crates/vendor`），编译时不联网。
- 安装步骤与 `make binary` 目标相同（`make install PORTABLE=1`，并复制 README、LICENSE、CHANGELOG），
  只是不在容器里打 tar 包。最后对 `bin/node` 执行 `strip`。

源码版本和 SHA-256 固定在 Dockerfile，SHA-256 取自官方 `SHASUMS256.txt`。
OpenSSL 3.5.9、ICU 78.3、libuv、V8、npm 11.20.0 等都用 Node 源码包自带的版本，随 Node 版本固定。
Alpine 的编译器和 rust 1.91.1 随 3.23 仓库更新，没有锁定到固定版本。

## 构建

在本目录执行，需要 Docker 和默认 buildx。脚本不创建 builder，也不安装模拟器。

```sh
sh ./build.sh amd64                                   # x86_64，本机 32 核约 45 分钟
ssh root@192.168.182.150 \
  'cd /root/workspace/mystatictools/node-static && sh ./build.sh aarch64 --build-arg BUILD_JOBS=8'
```

aarch64 在 ARM 主机（16 核、15 GB）上用 8 个并行任务，编译约 2 小时。

`BUILD_JOBS` 默认为 16。V8 编译很吃内存，内存在 16 GB 左右的机器上建议用 8。
同一架构不要在两台机器上同时构建，共享的 `dist/` 会互相覆盖。

`build.sh` 没有用 `type=local` 直接导出到 `dist/`。原因是产物里有 `bin/npm`、`bin/npx` 两个软链接，
而 ARM 主机通过 SSHFS 访问 `dist/`。BuildKit 对软链接执行 `lchown` 时，SSHFS 会跟随到目标文件，
于是报 `no such file or directory`，导出失败（已实际遇到）。从 SSHFS 读回这种 `../` 相对软链接也会报
`Operation not permitted`。所以脚本改为先导出成 tar，在本机临时目录解压、检查、打包，
再把 tar.gz 写入 `dist/`，并用 `tar --no-same-owner` 解压到 `dist/<架构>/`。
在 ARM 端用 `ls` 查看 `dist/aarch64/node/bin/npm` 时仍会看到读取失败，但文件本身正确，
以 x86 端（实际存储所在的一侧）或 tar 包内容为准。

产物：

```text
dist/node-v26.13.0-linux-x86_64-static.tar.gz      # 解压后是 node/ 目录，约 200 MB
dist/node-v26.13.0-linux-aarch64-static.tar.gz
dist/*.tar.gz.sha256
dist/<架构>/node/bin/node                          # 静态 ELF，约 120 MB
dist/<架构>/node/BUILD-INFO.txt                    # 版本、源码哈希、configure 选项、Alpine 版本
```

目录结构与官方二进制包相同：`bin/node`、`bin/npm`、`bin/npx`、`lib/node_modules/npm`、
`include/node`（编译原生扩展用的头文件，静态版用不上，保留是为了和官方包结构一致）。
Node 25 起官方包已不带 corepack，这里也没有。

## 使用

```sh
tar -xzf node-v26.13.0-linux-x86_64-static.tar.gz
./node/bin/node --version
export PATH=$PWD/node/bin:$PATH      # npm、npx 的首行是 #!/usr/bin/env node，需要 node 在 PATH 里
```

只运行 `node xxx.js` 时不需要 PATH，也不需要 shell。

## 能用的功能

下列项目已经由 `test/smoke-test.js` 实际测试过（见下文“验证记录”）：

- 版本、Intl（full-icu，`zh-CN` 月份名，`Asia/Shanghai` 时区换算）、`Temporal`
- crypto：SHA-256/SHA3、AES-256-GCM、Ed25519 签名、WebCrypto
- zlib：gzip、brotli、zstd；`node:sqlite`
- 文件读写、`child_process` 直接执行 node 自身、`worker_threads`
- 本机 HTTP 服务加 `fetch`，HTTPS/TLS（自签证书，只连 127.0.0.1）
- npm：离线 `npm pack` 本地目录，再 `npm install` 生成的 tgz

## 不能用或受影响的功能

- **原生扩展（`.node`）不能加载。** 静态 musl 程序没有动态加载器，`require` 会报
  `Dynamic loading not supported`（已实测）。依赖原生扩展的 npm 包（如 `node-pty`、
  原生版 `tree-sitter`、`bcrypt`、`sqlite3`）都不能用。纯 JS 或 WebAssembly 实现的包不受影响。
  这是纯静态链接必然带来的限制，需要原生扩展就只能用官方的动态版本。
- **用户名和主机名查询走 musl。** musl 只读 `/etc/passwd`、`/etc/group`、`/etc/hosts`、
  `/etc/resolv.conf`，不支持 glibc 的 NSS（`nsswitch.conf`、sssd、LDAP）。
  `os.userInfo()` 在 LDAP 用户下可能失败，DNS 也不走 systemd-resolved 的 NSS 模块。
- **CA 证书。** Node 自带 Mozilla CA 列表，访问公网 HTTPS 不依赖系统证书。内网自签 CA 用
  `NODE_EXTRA_CA_CERTS=/path/ca.pem` 指定。`--use-system-ca` 读取的是内置 OpenSSL 编译时的默认路径，
  不一定是目标系统的证书目录，未验证，不建议依赖。
- **npm 离线安装**只能用本地的 tgz 或目录。依赖较多的包需要先在联网机器上准备好
  （例如 `npm pack` 出所有依赖，或者打包整个 `node_modules`），再拷贝过去。
- `child_process.exec()` 和 `spawn(..., {shell: true})` 会调用系统的 `/bin/sh`，静态 node 本身不带 shell。

## 验证记录

2026-11-03，构建主机 Fedora 44 x86_64，Docker 默认 buildx：

1. 构建阶段：用 `readelf` 检查架构为 X86-64，无 `INTERP`，无 `NEEDED`，`file` 显示 `static-pie linked`。
   `--version` 输出 `v26.13.0`。
2. 构建容器（Alpine）里运行 `test/smoke-test.js`，14 项全部通过。
3. `FROM scratch` 空根文件系统，加 `RUN --network=none` 断网，只放 node 和测试资料，没有 shell、libc、
   证书：14 项全部通过。DNS 解析 localhost 那一项只做记录，Docker 构建时会注入 `/etc/hosts`，
   所以不能当作“没有 hosts 文件也能解析”的证据。
4. Fedora 44 宿主机（glibc）：`env -i` 清空环境变量，PATH 指向不存在的目录，直接运行导出的
   `dist/x86_64/node/bin/node`：14 项全部通过。

2026-11-03，aarch64 在原生 ARM 主机 192.168.182.150（Fedora 44，glibc 2.43）上用默认 buildx 构建，没有用模拟器：

1. 构建阶段的 `readelf` 和 `file` 检查与 x86_64 相同：AArch64，`static-pie linked`，无 INTERP，无 NEEDED。
2. 构建容器和 scratch 断网环境：14 项全部通过。
3. ARM 宿主机：把 tar 包解压到本地临时目录，用 `env -i` 清空环境变量，PATH 指向不存在的目录，
   直接运行：14 项全部通过。

两个 tar 包都在 x86 端用 `sha256sum -c` 校验通过，并检查了包内 `bin/npm`、`bin/npx` 软链接。

**还没验证的：**
- 实际运行语言服务器（yaml/json/bash）。这是下一步在 neovim 中接入时要做的事。
- 老内核（如 CentOS 7 的 3.10）和老 CPU 上能否运行。
- 访问公网 HTTPS 和公网 DNS。测试只连 127.0.0.1。

## 目录

```text
Dockerfile         # 编译、scratch 断网测试、导出
build.sh           # 构建入口，生成 dist/ 下的 tar 包和 sha256
pushfdoc.sh        # 发布到 fdoc 的 tools/node/，只在明确要求时运行
test/smoke-test.js # 功能测试，不调用 shell，可在 scratch 中运行
test/hello-addon.c # 最小 N-API 扩展，用来确认 .node 加载失败时的报错
test/local-pkg/    # npm 离线打包安装用的测试包
```

测试资料不打进运行包。

## 参考文档

- [Node.js BUILDING.md](https://github.com/nodejs/node/blob/v26.13.0/BUILDING.md)（编译要求、Rust 版本要求、`--fully-static`）
- [Node.js v26.13.0 下载与 SHASUMS256.txt](https://nodejs.org/dist/v26.13.0/)
- [nodejs/unofficial-builds recipes](https://github.com/nodejs/unofficial-builds/tree/main/recipes)
- [Node.js Intl 与 ICU](https://nodejs.org/docs/latest-v26.x/api/intl.html)
- [Node.js C++ addons / N-API](https://nodejs.org/docs/latest-v26.x/api/addons.html)
- [musl 与 glibc 的功能差异](https://wiki.musl-libc.org/functional-differences-from-glibc.html)
