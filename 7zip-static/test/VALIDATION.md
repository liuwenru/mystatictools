# 26.05 验证记录

日期：2026-10-24。

| 架构 | 构建及复测主机 | 方式 | 7zz 大小 |
| --- | --- | --- | --- |
| x86_64 | 192.168.188.150 | Alpine 3.22 容器原生构建，宿主 chroot 原生复测 | 2,840,976 字节 |
| aarch64 | 192.168.182.150 | Alpine 3.22 容器原生构建，宿主 chroot 原生复测 | 2,754,856 字节 |

两端均使用默认 buildx，未使用 QEMU，未安装或修改模拟器及 builder。
共享目录为 `/root/workspace/mystatictools`，两种架构分别导出，没有互相覆盖。

## 结果

- 版本 26.05，ELF Machine 分别为 X86-64 / AArch64。
- `file` 显示 statically linked；`readelf -l` 无 INTERP，`readelf -d` 无动态节及 NEEDED。
- 两种架构均在构建阶段和导出后通过 `smoke-test.py` 全部测试。
- 已测 7z/ZIP/tar 往返、中文及空格文件名、空文件、随机文件。
- 已测 gzip/bzip2/xz 与 Python 标准库双向互通，以及 Python 解压生成的 ZIP。
- 已测 7z 文件头加密、ZIP AES256、正确密码逐字节恢复及错误密码失败。
- 已测 stdin/stdout、SHA-256 对比及截断归档失败。
- 已检查两个运行包只含 7zz、三份许可证、SHA256SUMS，没有测试或临时文件。

测试 chroot 中无动态库、shell 或插件；`/dev/null` 和 `/dev/urandom` 为专用测试文件。
随机种子文件由宿主 Python 的安全随机源生成，仅用于验证功能，不能复制用于生产。
真实运行环境应提供正常的 `/dev/urandom`。

## 二进制 SHA-256

```text
6e2c01776c808ac9c42bbfd9799dab008b560690f72646bd13032528d649ae4c  x86_64/7zz
7ea14eb2c7ce4ba5148d659e375a35914c6a4f211b0a00038615776265bcdef8  aarch64/7zz
```

## 未验证

未遍历所有格式；RAR/RAR5 仅验证内置格式注册，未测试真实 RAR 样本。
未运行上游完整测试套件、性能基准，未在用户实际离线业务环境或旧内核/CPU 上验证。
