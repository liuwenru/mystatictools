# 验证记录

## 构建门禁

`Dockerfile` 中的 ELF、版本、空根目录、模块、补全、环回 TCP 和 PTY 测试必须全部通过，
才会导出产物。结果随架构保存到 `dist/<架构>/test-results.txt`。
这些门禁不依赖 glibc、宿主机 shell 配置或外部网络服务。

2026-10-21 实际构建结果：

| 架构 | 执行方式 | 构建门禁 | 导出后二次 SHA-256 校验 |
| --- | --- | --- | --- |
| x86_64 | 原生 Docker 容器 | 全部通过 | 通过 |
| aarch64 | 宿主机已有 QEMU/binfmt | 全部通过 | 通过 |

两种架构均确认无 ELF 动态解释器和 `NEEDED`，38 个 zsh 静态模块均可激活。

## 补充上游回归：amd64

在构建阶段镜像中额外运行上游测试，**没有把所有回归项都描述为通过**。
上游测试使用构建树中的未 strip ELF，与交付 ELF 来自同一次编译。

### zsh 5.9.2

执行 `make -C /build/zsh check`：**61 个测试脚本成功，4 个失败**，部分脚本内部用例因 root、
终端环境或 libc 不支持相应扩展而跳过。

4 个失败脚本均观察到 musl `LC_ALL=C` 高位字节映射差异：

| 脚本 | 观察到的预期/实际差异 |
| --- | --- |
| A03quoting | `0xdc` / `0xdfdc` |
| B03print | `0xf0` / `0xdff0` |
| D04parameter | `128,129` / `57216,57217`，即 `0xdf80,0xdf81` |
| E02xtrace | 高位字节转义 / `\udfe3\udf83\udf8c` 转义 |

这与 musl 文档所述 C locale 将 `0x80..0xff` 映射到宽字符 surrogate 区间的语义相符。
不通过禁用 multibyte、改测试预期或替换 libc 来隐藏差异。UTF-8 中文交互及上游 D07multibyte
测试已通过，但处理任意二进制字节或比较转义文本时，不能假设输出与 glibc 完全相同。

### Bash 5.3.20

先运行 root 测试发现上游明确不建议以 root 执行，随后在独立容器中将构建树交给 nobody，
以非 root 重跑 `make tests`。

**86 个测试组执行结束，13 组存在 diff**：

```text
run-builtins run-cond run-execscript run-exp-tests run-glob-bracket
run-glob-test run-history run-intl run-read run-test run-trap
run-varenv run-vredir
```

已观察到动态 `.so` 测试无法执行、musl locale/正则差异、缺少 Big5/非 UTF-8 locale、
容器无控制终端，以及继承的 SIGQUIT 状态和其他文本输出差异。
**未逐条证明所有 diff 都无害，不以 `make tests` 退出码 0 作为全部测试通过的证据。**
实际 PTY 编辑、Tab 补全、中文整字符退格、停止/恢复任务、信号，以及数组、正则、
进程替换和协进程另有专门的门禁测试。

完整补充日志保存在当前交付的 `dist/x86_64/upstream-tests/`。
这组补充上游回归未在 aarch64 重跑；aarch64 只执行与 amd64 相同的构建门禁测试，
且模拟器结果不能替代真实目标机验证。

## 复现补充回归

在项目目录执行，仅使用默认 builder。以下容器改动只发生在一次性容器内：

```sh
docker buildx build --builder default --platform linux/amd64 \
  --target zsh-builder --load -t zsh-bash-static-check:amd64 .
docker run --rm --network none zsh-bash-static-check:amd64 \
  make -C /build/zsh check

docker buildx build --builder default --platform linux/amd64 \
  --target bash-builder --load -t bash-static-check:amd64 .
docker run --rm --network none bash-static-check:amd64 sh -ec \
  'chown -R 65534:65534 /build/bash; exec su nobody -s /bin/sh -c "cd /build/bash && make tests"'
```
