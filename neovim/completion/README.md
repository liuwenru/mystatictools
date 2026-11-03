# 离线配置关键字补全

不需要 LSP、Python、Node 或联网。配合仓库的 `init-offline.lua`，从本目录的 JSON 词库
生成候选，确认时**只插入关键字本身**，不附加引号、冒号、等号、分号或示例配置。
按 `↑/↓` 或 `Ctrl+p/n` 选择，已选候选时用 `Enter` 或 `Ctrl+y` 确认，`Ctrl+e` 取消。
Enter 确认不额外换行；未选候选或无菜单时正常换行，方向键无菜单时正常移动，不修改 Tab。
选中候选后可查看说明弹窗。冒号命令菜单也支持 `↑/↓`，已选候选时第一次 Enter 只确认，
第二次才执行；无菜单或未选择时 Enter 仍正常执行命令。详见 `:OfflineHelp completion`。

## 目录

```text
init.lua              # 纯 Lua 补全来源
generated/*.json       # 自动提取结果，不建议手改
custom/*.json          # 中文简释、手工增补、覆盖和禁用，重新生成不会改这里
sources.json           # 来源 URL、固定提交/版本、抓取日期、SHA-256
sources/               # 原始 Schema / XML / help / Go / MDN Markdown 快照，仅进入源码包
licenses/              # 上游许可证，随运行包和源码包保留
```

构建时将 `init.lua`、本说明、`generated/`、`custom/` 和 `licenses/` 安装到
`nvim/completion/`。原始资料、清单、提取脚本保留在源码包的 `sources/build/`，不放入运行包。
Lua 相对自身位置读取词库，不扫描工作目录、不执行词库内容。移动完整安装目录后仍有效。

## 九类默认匹配

| 词库文件 | 自动匹配 | 资料范围 |
| --- | --- | --- |
| `opencode.json` | `opencode.json` / `opencode.jsonc` | 官方配置 Schema 的非废弃字段，默认面向 V2 |
| `compose.json` | `compose.yaml/yml`、`docker-compose.yaml/yml`，以及 `compose.override.yaml`、`docker-compose.prod.yml` 等带后缀文件 | Compose Specification 官方 Schema |
| `nginx.json` | `nginx` 文件类型 | core/events；HTTP core、proxy、upstream、SSL、rewrite、headers、log、gzip、access、realip、map、限流、index、autoindex、auth_basic、auth_request、FastCGI、HTTP/2；stream core、proxy、upstream、SSL、log、map、access、realip、limit_conn |
| `systemd-service.json` | `*.service`（含 `name@.service`）、`*.service.d/*.conf` | systemd.unit/service/exec/kill/resource-control 的字段和三种段落名 |
| `tomcat.json` | `server.xml` | Tomcat 9.0.123 / 10.1.61 配置文档中的元素及属性；Server、Service、Connector、Executor、Engine、Host、Context、Realm、Valve、Listener、TLS 证书等 |
| `redis.json` | `redis.conf` | Redis 8.10.2 官方配置样例，与配置指令注册表取交集；不收集 GET/SET 等客户端命令 |
| `dockerd-cli.json` | Shell（sh/bash/zsh）当前行的简单 `dockerd --选项` 命令 | 本机 `/usr/bin/dockerd` 27.3.1（41ca978）的帮助：85 个长选项、8 个短选项 |
| `docker-daemon.json` | `daemon.json` | Moby v27.3.1 Linux 配置定义：80 个根字段、25 个嵌套字段 |
| `http-headers.json` | `.http` / `.rest` 或 `http` 文件类型的头部区域；Nginx 指定指令的头名称位置 | MDN 固定提交的 74 个常用 Header；含认证、缓存、内容、CORS、安全、代理、WebSocket |

`compose` 在自动模式下只兜底：示例配置把同一份 Schema 快照（构建时装到 `nvim/completion/schemas/`）
交给随包的 yaml 语言服务器，服务器附加到缓冲区后由它按层级补全和校验，词库不再给出重复候选；
服务器没有附加时仍用词库。手动 `:OfflineCompletion compose` 仍强制使用词库。
`opencode` 不这样做：它的 Schema 用 `$ref` 引用外部 models.dev 的模型表，交给 json 服务器会联网下载。

不把所有 YAML/JSON/`.conf` 都启用词库。自定义文件名可以在当前缓冲区手动选择：

```vim
:OfflineCompletion opencode
:OfflineCompletion compose
:OfflineCompletion nginx
:OfflineCompletion systemd-service
:OfflineCompletion tomcat
:OfflineCompletion redis
:OfflineCompletion dockerd-cli
:OfflineCompletion docker-daemon
:OfflineCompletion http-headers
:OfflineCompletion off
:OfflineCompletion auto
```

`off` 只关闭关键字词库，不影响路径、当前文件单词或已有 LSP；命令不改变文件类型。
需要全部关闭，用会话级 `:OfflineCompletionAll off`，恢复用 `on`、切换用 `toggle`；无参数只查询。
总开关同时暂停所有缓冲区（含后续打开）的自动和插入模式手动补全，保留 LSP 的诊断/跳转。
恢复时还原原有选项/按键，不更改当前词库选择；不写永久配置，也不管理另装的第三方补全插件。
`Ctrl+x` 前缀的其他用途也暂时不可用；关闭期间不要重新 source 配置或另行改动补全选项/按键。
在 Neovim 中用 `:OfflineHelp completion` 查看详细操作和开关区别，Header 专题用 `:OfflineHelp headers`。
Nginx 自定义 `.conf` 若还需要高亮，可另用 `:set filetype=nginx`。
systemd 服务 drop-in 自动使用 `systemd` 文件类型；其他 `.conf` 不受影响。

## 手工补录

例如编辑 `custom/nginx.json`，向 JSON 数组追加：

```json
{
  "word": "my_directive",
  "description": "团队自定义模块的指令说明",
  "context": "location",
  "syntax": "my_directive value",
  "module": "团队模块"
}
```

字段：`word` 必填，其他均可省略。`context` 为位置说明；`description` 为说明；
`syntax` 为语法提示；`module` 为模块；`version` 为版本提示；`source` 为参考链接；
`values` 为字符串数组，用于在说明中展示枚举值，**不自动补入值**；`type` 为类型名称的字符串数组。
`default` 为字符串，展示本机帮助中的默认值；仅覆盖 description 时仍保留生成的类型、默认值和枚举。
Tomcat 新增项可指定 `kind` 为 `element`（元素名）或 `attribute`（属性名）；省略时会在两种位置都提示。

- 只写 `word` 和 `description`：覆盖所有同名生成条目的说明，保留原来的上下文/语法等。
- 加上 `context`：只覆盖相同 word/context 的条目；没有匹配项时新增。
- `{"word":"some_directive","disabled":true}`：隐藏生成词库中的该关键字。
- 同名关键字在菜单中合并为一个候选，说明中保留多个位置或模块。

修改后执行 `:OfflineCompletionReload`，下次补全重新读取，不必重新编译。
运行包中修改 `nvim/completion/custom/` 可直接重载；修改仓库词库则需同步至运行目录或重新打包。
词库格式错误会提示文件路径；错误 custom 文件不影响生成词库及原有补全。

## 更新生成词库

在仓库 Neovim 目录执行（只需维护机器有 Python 3）：

```sh
python3 ./generate-completion.py          # 校验快照哈希，离线重建 generated/
python3 ./generate-completion.py --check  # 只比对，不写文件
python3 ./generate-completion.py --download  # 用清单 URL 补齐缺失快照，仍严格校验哈希
python3 ./test/dictionary-generation-test.py
```

脚本处理 `properties`、动态对象、数组、`$ref`、`allOf/anyOf/oneOf`、枚举值，跳过标记
`deprecated` 的节点/分支；引用的文档必须预先列入清单，缺失则报错，不在提取中随意追踪网页。
递归引用终止并记录在生成结果中；这是字段提取器，不实现完整 JSON Schema 语义。
Tomcat 提取文档中的属性表，区分元素/属性并保留版本和协议/实现说明；Redis 只提取在
配置解析器注册且出现在官方样例中的指令，保留参数样例，不将说明文字直接当关键字。
Docker CLI 从保存的本机 `--help` 提取，JSON 字段独立读取固定版本 Go 配置结构；不是把 CLI 去掉 `--`。
根字段限制为本机帮助确认的公开项、明确的复数映射及 builder/proxies，内部或隐藏字段不全部提取。
Go 读取器仅面向这些快照，支持嵌入结构和已核对的自定义 JSON 类型，不是通用 Go/JSON 分析器。
`local:` 来源必须手工提供快照，`--download` 不执行本机 dockerd；更换版本须同步核对帮助和源码。
HTTP Headers 使用 MDN content 提交 `bd5271a96d814ed6876e974186c465f1b3959e07` 的精选页面，
不把索引中所有字段全部收录；从属性表、简介和 Syntax 提取类型/说明/语法，不执行 MDN 模板。
跳过元数据标记 deprecated/experimental 的页面，`X-Forwarded-*` 保留但标明非标准。
已有生成结果变化时会先留隐藏备份，不动 custom；备份不进入 Docker 构建上下文。

新增或更新来源需要明确修改快照和 `sources.json` 中的 URL/提交/版本/日期/哈希，检查后再生成。
OpenCode Schema URL 随上游更新，因此保留本地快照；未来从原 URL 下载可能因哈希不同而失败，
不能为了通过校验悄悄替换哈希。构建只检查本地快照，不联网更新关键字。

## 边界与许可

- 第一版按文件类别和前缀提示；除 HTTP Header 名称外均区分大小写，位置只作说明，**不按配置层级过滤或校验**。
  Compose 需要分层和校验时由语言服务器提供（见上文），词库本身仍不分层。
  Compose 动态服务名、环境变量名不会作为固定词条提取；`*`、`[]` 只是说明中的路径占位。
- 用简单行内规则避免在常见值/注释位置提示；不完整解析 JSONC 块注释、YAML 多行标量等语法。
  路径上下文只交给路径来源，避免词库/LSP 的替换起点冲突；保留原有正文和可选 LSP 补全。
- Schema 标记废弃的节点/分支默认不提取；其他来源不保证识别所有兼容/废弃条目。
  Nginx 默认排除明确标为商业专属的指令，不代表每个语法参数都属于开源版。
  非默认模块仍需目标 Nginx 实际编译/加载；没有标注版本的条目不代表兼容所有旧版本。
- systemd 基于 v262.1 文档；有明确版本标记才提取，某些条目的标记反映成组文档变更，
  不是严格的逐选项/逐枚举兼容矩阵。常用枚举也是提示列表，不代表完整可用值。
- Tomcat 按 XML 名称大小写补全：`<Con` / `</Con` 提示元素，`<Connector maxT` 提示属性，
  支持跨行标签、属性中的点号；不自动补 `>`、`/>` 或 `=""`。词库区分元素和属性，但不按父子层级、
  当前标签或运行版本严格过滤；提示的属性不一定适用于当前 Connector 实现或当前元素。
  使用最近 200 行做轻量词法扫描，跳过引号、注释和 CDATA；更长的跨行结构不能保证识别。
- Redis 只在行首指令位置提示，不补全参数值，不自动去掉注释。只自动匹配 `redis.conf`；
  `redis-prod.conf` 等名称用 `:OfflineCompletion redis` 选择。8.x 新指令不保证适用于 6.x/7.x，
  不收集 Sentinel 配置或第三方模块专属指令，不代表目标 Redis 构建支持 TLS 或外部模块。
- dockerd CLI 仅在当前行简单命令的选项名位置触发，支持绝对路径及 sudo/exec 前缀；
  不解析 sudo 参数、变量赋值、Shell 函数、跨行引号/heredoc 或续行。当前行注释、未闭合引号、
  转义、替换、管道和重定向不触发。特殊位置（如 ExecStart）用 `:OfflineCompletion dockerd-cli`；
  手动选择仍只补 `-` 开头的选项，不补参数值。复杂多行 Shell 请关闭词库或手动选择，不把它当语法解析器。
  默认值来自此主机/root 环境，例如证书路径可能含 `/root`，不是所有主机的通用默认；不凭空补 false 默认值。
- daemon.json 保持严格 JSON，不补引号/冒号/值，不按嵌套位置过滤；`proxies.http-proxy`、
  `runtimes.*.path`、`builder.gc` 等路径仅作说明。未带 JSON tag 的嵌套字段用 lower-camel 提示，
  不代表大小写唯一形式。`--host` 对应 hosts、`--log-opt` 对应 log-opts、`--add-runtime` 对应 runtimes；
  help/version/validate/config-file 等 CLI 专用项不进入 JSON 词库。配置项与启动参数重复可能导致启动失败。
  仅面向本机 27.3.1/Linux，不能据此保证其他 Docker 版本或 Windows 支持；不读取真实 daemon.json。
- HTTP Header 名称忽略大小写，菜单使用常见书写形式；原生补全可能保留已输入前缀的大小写，
  不强制改成全小写或 Title-Case。只插名称，不补冒号、值或分号；语法和枚举仅供参考，不是安全配置建议。
  手工补录用 `custom/http-headers.json`，word 建议与生成条目的书写形式一致，以便覆盖/禁用。
  在普通文本中 `:OfflineCompletion http-headers` 可提示独立的名称前缀，不在任意 JSON 字符串中猜测。
  词条分类保留 MDN 属性表，个别条目分类不完整（例如 Sec-WebSocket-Version），以说明和目标协议为准；
  不按请求/响应方向过滤，浏览器禁止脚本设置的字段也不等同于服务器不能发送。
- `.http` / `.rest`：支持简单请求行（GET/HEAD/POST/PUT/DELETE/PATCH/OPTIONS/CONNECT/TRACE）
  或 `HTTP/1.x 状态码` 后的头部，首个空行进入正文，`###` 行分隔下一次请求；HTTP/2、HTTP/3 状态行文本也可识别，
  但这不是线上二进制协议解析。跳过头部中的 `#`、`//` 注释，不补请求地址、已有冒号后的值或正文。
  只做 REST-client 文本的轻量识别，不执行请求，不解析模板、脚本、折叠头或所有客户端专有语法。
  正文内 `###` 行仍按请求分隔处理；不收录 :authority/:method 等伪首部。
- Nginx 自动模式在当前行 `add_header`、`add_trailer`、`proxy_set_header`、`proxy_hide_header`、
  `proxy_pass_header` 的第一个参数位置切换为 Header 候选，支持未闭合的单/双引号名称及同一行前面的 `{`/`;`。
  不在值、注释、变量中提示；不解析跨行指令、跨行引号或转义。其他位置保持原有指令补全。
  `:OfflineCompletion nginx` 会固定为原来的 Nginx 指令词库，恢复上下文切换请用 `auto`。
  HTTP/2/3 禁止 Connection、Keep-Alive、Transfer-Encoding 等连接专用字段；代理头必须按可信代理边界处理。
- 常用项通过 custom 补充中文简释，其他说明沿用上游英文。说明/语法由上游资料抽取、重排和截短，
  不是上游原件，也不构成配置建议；分别保留原始来源和许可证：Compose Apache-2.0，
  Nginx 官方文档 BSD 风格许可，systemd 文档 LGPL-2.1-or-later，OpenCode 见其 LICENSE，
  Tomcat Apache-2.0（含 NOTICE），Moby 与 docker/go-units Apache-2.0。Redis 8.10.2 来源提供 RSALv2/SSPLv1/AGPLv3 选择，
  此处来源资料按 AGPLv3 选项使用，同时保留旧 BSD 部分的贡献声明；快照和提取脚本随源码包提供。
  MDN 文本与基于其改编的 HTTP 词库说明按 CC-BY-SA-2.5，作者为 MDN Web Docs contributors，
  署名、原文及改动说明见 `licenses/mdn-headers-ATTRIBUTION.md`，完整上游许可见 `licenses/mdn-content-LICENSE.md`。
  生成词库继承相应资料的许可要求，不改变 Neovim 或其他工具的许可。
- 最终有效性仍用目标版本的 `docker compose config`、`nginx -t`、`systemd-analyze verify` 检查。
