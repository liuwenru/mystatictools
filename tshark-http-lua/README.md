# TShark + Lua HTTP 实时抓包分析

使用项目自带的静态 TShark 和 Lua 脚本，按响应 TCP 包输出时间、连接信息和
原始 payload。既可以分析已有 PCAP，也可以实时抓包；提供 TLS key log 时，
还会在原始 TLS 密文后附加可用的 HTTP/1 或 HTTP/2 解密内容。

## 主要用途

- 观察服务端每个响应 TCP 包的到达时间和载荷；
- 计算请求首包到响应包的耗时；
- 计算同一 TCP stream 中相邻响应包的时间间隔；
- 分析 HTTP 流式响应、SSE 或类似实时传输；
- 保留原始 TCP 包边界，同时查看能够完成 TLS 解密的明文块。

该工具侧重报文时序，不是完整的 HTTP 内容导出器。

## 目录说明

```text
tshark-http-lua/
├── dumpcap                 # TShark 调用的架构分发脚本
├── dumpcap-aarch64         # ARM64 静态抓包程序
├── dumpcap-x86_64          # x86_64 静态抓包程序
├── http_export.lua         # TCP 时序及 HTTP/TLS 内容输出逻辑
├── mockrequest.py          # HTTPS 解密测试请求
├── run.sh                  # 离线分析和实时抓包入口
├── tshark-aarch64          # ARM64 静态分析程序
└── tshark-x86_64           # x86_64 静态分析程序
```

`http_output.txt`、`*.pcap` 和 `*.pcapng` 是运行产生的数据文件，不是程序依赖。

## 平台与权限

当前支持 `uname -m` 返回以下值的 Linux 平台：

- `x86_64`；
- `aarch64`。

`run.sh` 会自动选择同目录下的 `tshark-$(uname -m)` 和
`dumpcap-$(uname -m)`，不会调用系统安装的 TShark 或 dumpcap。

首次使用确认脚本可执行：

```bash
chmod +x run.sh dumpcap
```

以 root 运行并加载 Lua 前，需要在 Wireshark 配置中启用：

```text
run_user_scripts_when_superuser = true
```

查看当前架构和 TShark 信息：

```bash
uname -m
./tshark-$(uname -m) --version
```

查看可抓取的网卡：

```bash
./tshark-$(uname -m) -D
```

## 快速开始

### 分析已有 PCAP

默认读取 `llm.pcap`，把 8900 作为服务端端口，结果写入
`http_output.txt`：

```bash
./run.sh
```

完整格式：

```text
./run.sh [pcap文件] [输出文件] [服务端端口] [客户端端口]
```

指定服务端端口：

```bash
./run.sh capture.pcap output.txt 8900
```

只分析客户端临时端口为 35444 的连接：

```bash
./run.sh capture.pcap output.txt 8900 35444
```

`客户端端口`始终可省略。省略时分析该服务端端口上的所有连接。

### 实时抓包并分析

默认监听 `any`，抓取 8900 端口，把原始报文写入 `llm.pcap`，并把 Lua
分析结果持续写入 `http_output.txt`：

```bash
./run.sh capture
```

完整格式：

```text
./run.sh capture [网卡] [pcap文件] [输出文件] [服务端端口] [客户端端口]
```

常用示例：

```bash
# 所有网卡上的 8900 端口
./run.sh capture any llm.pcap http_output.txt 8900

# 本机回环接口上的 8000 端口
./run.sh capture lo local.pcap local_output.txt 8000

# 限定一条客户端临时端口为 35444 的连接
./run.sh capture any llm.pcap http_output.txt 8900 35444
```

按 `Ctrl+C` 停止抓包。使用 `any` 时出现下面的提示通常不影响抓包：

```text
Promiscuous mode not supported on the "any" device.
```

## 参数含义

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| 网卡 | `any` | 实时模式监听的接口，如 `any`、`ens192`、`eth0`、`lo` |
| PCAP 文件 | `llm.pcap` | 离线输入文件，或实时模式保存的原始抓包 |
| 输出文件 | `http_output.txt` | Lua 分析文本 |
| 服务端端口 | `8900` | 抓包中服务端响应包的 TCP 源端口 |
| 客户端端口 | 空 | 可选；用于限定一条连接 |

服务端端口决定以下行为：

- 实时模式的 BPF 抓包过滤器；
- Lua 中请求和响应方向的判断；
- 设置 `SSLKEYLOGFILE` 后强制识别 TLS 的 TCP 端口。

因此这里必须填写抓包中实际看到的 TCP 服务端端口，而不只是 URL 中的逻辑端口。

## 输出说明

每个服务端响应 TCP 包包含类似信息：

```text
frame.number               : 21
frame.time                 : 2026-07-21T17:43:26.430592107+0800
frame.time_epoch           : 1784627006.430592107
tcp.stream                 : 0
network                    : 192.168.0.88:8900 -> 192.168.188.150:35444
tcp.payload_bytes          : 7728
time.since_request_ms      : 57.904
time.since_previous_tcp_ms : 7.985
--- TCP PAYLOAD BEGIN ---
...
--- TCP PAYLOAD END ---
```

- `time.since_request_ms` 从该 stream 首个带载荷请求包开始计算；
- `time.since_previous_tcp_ms` 是同一 stream 中相邻响应包的间隔；
- `TCP PAYLOAD` 始终是线上原始 `tcp.payload`；
- 合法 UTF-8 原样显示，其他二进制字节转义为 `\xNN`。

如果抓包不是从连接开始，`time.since_request_ms` 可能显示 `unknown`。

## HTTPS 解密

### 使用方法

启动产生 HTTPS 流量的应用程序前设置 NSS key log 文件：

```bash
export SSLKEYLOGFILE=/root/python-tls.keys
```

实时抓取标准 HTTPS 端口：

```bash
./run.sh capture any https.pcap https_output.txt 443
```

然后在同样设置了该环境变量的环境中启动客户端程序：

```bash
export SSLKEYLOGFILE=/root/python-tls.keys
python3 mockrequest.py
```

如果抓包和客户端位于两个终端，两个终端都必须导出相同的
`SSLKEYLOGFILE`。只给 `run.sh` 设置变量不会让 Python、Java 或其他客户端
自动产生会话密钥。

离线解密使用相同方式：

```bash
export SSLKEYLOGFILE=/root/python-tls.keys
./run.sh https.pcap https_output.txt 443
```

### 解密输出

设置 `SSLKEYLOGFILE` 后，`run.sh` 会：

- 向 TShark 传入 `tls.keylog_file`；
- 将指定服务端端口强制识别为 TLS；
- 关闭 HTTP 正文整体重组，避免流式响应等到结束才集中输出；
- 保留每个 TCP 包的原始 TLS 密文；
- 在可用时附加 HTTP/1、HTTP/2 或通用 TLS application data 明文。

示例：

```text
--- TCP PAYLOAD BEGIN ---
...原始 TLS 密文...
--- TCP PAYLOAD END ---
--- DECRYPTED HTTP/1 FILE DATA BEGIN (1/1, available at frame 21) ---
...解密后的 HTTP 内容...
--- DECRYPTED HTTP/1 FILE DATA END ---
```

### TLS 与 TCP 边界

TLS record 和 TCP 包没有一一对应关系。一个 TLS record 可能跨多个 TCP 包，
也可能一个 TCP 包中包含多个 TLS record。必须收到完整 record 和认证标签后才能
解密，因此明文会归属到完成解密的那个帧，并通过 `available at frame` 标记。

脚本不会修改、合并或伪造前面 TCP 包的到达时间。TLS record 重组是认证解密的
必要步骤，但原始 TCP 包输出仍保持不变。

### HTTP 内容压缩

为了保持实时输出，脚本不会跨 HTTP chunk 合并并解压 `gzip`、`br` 等内容编码。
TLS 可能已经成功解密，但明文块仍是压缩后的 HTTP body。例如 gzip 通常以
`1F 8B` 开头。

测试或需要直接查看文本时，建议客户端发送：

```http
Accept-Encoding: identity
```

Python requests 示例：

```python
response = requests.get(
    "https://example.com",
    headers={"Accept-Encoding": "identity"},
)
```

## 代理注意事项

当前脚本主要面向直连 HTTP/HTTPS。

使用显式 HTTP、HTTPS 或 SOCKS 代理时，客户端 TCP 连接的服务端是代理，抓包中
看到的服务端端口可能是 `1080`、`3128` 等代理端口，而不是目标网站的 `443`。
HTTP `CONNECT` 还会让明文代理握手和隧道内 TLS 共用同一 TCP stream；HTTPS
代理可能出现外层代理 TLS 和内层目标 TLS。

当前脚本会把设置的服务端端口整体强制识别为 TLS，因此不能保证正确处理这些
代理隧道。排查时先检查输出中的 `network`，确认连接对端是否为目标服务器：

```text
network : 服务端IP:服务端端口 -> 客户端IP:客户端临时端口
```

如果显示的是代理地址或代理端口，需要单独处理代理隧道，不能直接把目标 URL 的
443 当作当前脚本的服务端端口。

## 常见问题

### 没有任何输出

确认 PCAP 中存在指定服务端端口的响应载荷：

```bash
./tshark-$(uname -m) \
  -r llm.pcap \
  -Y "tcp.srcport == 8900 && tcp.len > 0"
```

还应检查：

- 服务端端口是否正确；
- 抓包接口是否包含目标流量；
- 客户端端口是否填错；
- PCAP 是否包含服务端响应 payload。

### HTTPS 只有密文，没有 DECRYPTED 块

检查以下项目：

- `SSLKEYLOGFILE` 是否在启动客户端前设置；
- 客户端和 `run.sh` 是否使用同一个 keylog 路径；
- keylog 是否包含本次新连接的 secrets，而不是旧连接数据；
- 是否从 TLS 握手开始抓包；
- 服务端端口是否是抓包中实际看到的 TCP 源端口；
- 是否经过显式代理。

可以先确认 keylog 中存在类似记录：

```text
CLIENT_TRAFFIC_SECRET_0 ...
SERVER_TRAFFIC_SECRET_0 ...
```

### DECRYPTED 块仍然看不到中文

先检查明文块是否以 `\x1F\x8B` 开头；如果是，说明 TLS 已解密，但 HTTP body
使用了 gzip。让客户端发送 `Accept-Encoding: identity` 后重新建立连接。

### root 下没有 Lua 输出

确认全局 Wireshark Lua 配置已经启用：

```text
run_user_scripts_when_superuser = true
```

脚本不会自动降权，也不会绕过该配置。

## 已知限制

- 暂不处理 HTTP/3/QUIC；
- 不对 gzip、Brotli 等 HTTP 内容编码做跨块流式解压；
- 显式代理和嵌套 TLS 隧道不是当前脚本的主要支持场景；
- 只输出服务端到客户端方向的带载荷 TCP 包；
- 抓包缺少请求方向或连接开头时，请求耗时可能为 `unknown`。
