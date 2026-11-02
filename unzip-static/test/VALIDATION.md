# UnZip 6.0（Ubuntu 6.0-31ubuntu1）验证记录

日期：2026-10-31。

| 架构 | 构建主机 | 方式 | unzip 大小 | funzip 大小 |
| --- | --- | --- | --- | --- |
| x86_64 | 本机（x86_64，Fedora 44，内核 7.2.9） | Alpine 3.22 容器原生构建及测试 | 435,344 字节 | 54,720 字节 |
| aarch64 | 192.168.182.150（aarch64，Fedora 44，内核 7.2.9） | Alpine 3.22 容器原生构建及测试 | 467,960 字节 | 66,912 字节 |

两端均使用默认 buildx，未使用 QEMU，未安装或修改模拟器及 builder。
两种架构分别导出到 `dist/x86_64`、`dist/aarch64`，没有互相覆盖。

## 结果

- `unzip -v`：`UnZip 6.00 of 20 April 2009, by Debian`，含 USE_BZIP2（bzip2 1.0.8）、ZIP64_SUPPORT、
  LARGE_FILE_SUPPORT、UNICODE_SUPPORT、USE_DEFLATE64。
- ELF Machine 分别为 X86-64 / AArch64；unzip、funzip `readelf -l` 无 INTERP，`readelf -d` 无 NEEDED。
- 两种架构结果相同：
  - 上游 `make check`：全部通过（testing complete，无 ERROR）。
  - Ubuntu autopkgtest：运行 34 项，0 失败，0 跳过；排除 5 项手册页、6 项 zipgrep（原因见 README）。
  - `smoke-test.py`：37 项全部 PASS。
- 宿主直接运行（`env -i`）：两台主机上 `LANG=zh_CN.UTF-8` 自动识别、`-O CP936` 手动指定，
  均正确解出 GBK 编码的 `中文目录/报表.txt`。
- 运行包只含 unzip、zipinfo（符号链接）、funzip、三个手册页、LICENSE.unzip、SHA256SUMS，`sha256sum -c` 通过。

## 二进制 SHA-256

```text
27e3f1e66013a34310f06ef683711addbe61f17236cb33bfed0d29cb29aaec21  x86_64/unzip
64856dd97805c17f900e789eea4f5462a2aab8f1ea6f0dee440efb973f8393e7  x86_64/funzip
6512a213465e48b1c93475beae93c26826f9fd73deb376715b2210b61909a490  aarch64/unzip
2e8a5f097c9074df3cdbf5c21550c54faa7ec59dae97ffe2a320e0b256868277  aarch64/funzip
```

## 构建中发现并处理的问题

- musl iconv 不认 `CP936`（GBK、GB18030 可用），中文 locale 自动识别和 `-O CP936` 都会失败、文件名乱码：
  加本地补丁 `patches/musl-iconv-cp936.patch`，打不开 CP936 时改用 GB18030。
- Debian 补丁集没有 `-O`/`-I`：改用包含 Debian 全部补丁的 Ubuntu 补丁集。
- Ubuntu autopkgtest 在 Alpine 中：umask 需为 002；手册页用例依赖 man-db（Alpine 的 man-db 因 musl iconv
  不支持 `//IGNORE` 无法渲染）；zipgrep 用例受 GNU grep 3.8+ egrep 警告和 busybox sed 差异影响。
  前者设置 umask，后两类排除，手册页改用 mandoc 检查。

## 测试环境限制

- 构建容器中以 root 运行；非 root 用户下的 `-X` 行为未测。
- Zip64 只验证了 force_zip64 写入的扩展字段解析，未用超过 4 GiB 的真实文件测试；Ubuntu 测试的大文件为 500 MiB。

## 未验证

- 超过 4 GiB 的单个成员、超过 65535 个成员的 zip。
- CP852、CP857 等 musl 不支持的 DOS 代码页在对应 locale 下的表现（预期为不转换，未实测）。
- 用户实际离线目标机器、旧内核。
