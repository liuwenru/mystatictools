-- 真实语言服务器测试：用 examples/init.lua 启动随包的 ty、TypeScript 7 和静态 node 运行的
-- yaml/json/bash 服务器，检查补全候选和诊断。TEST_ROOT 必须是一次性的独立目录。
-- 运行：nvim --headless -u <nvim>/examples/init.lua -i NONE -c "lua dofile('lsp-bundled-test.lua')"
local root = assert(vim.env.TEST_ROOT, 'TEST_ROOT is required') .. '/lsp-bundled'
local libexec = vim.fn.fnamemodify(vim.uv.exepath(), ':h:h') .. '/libexec/'
local timeout = tonumber(vim.env.TEST_LSP_TIMEOUT or '') or 60000

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(root .. '/' .. path), 'p')
  vim.fn.writefile(lines, root .. '/' .. path)
  return root .. '/' .. path
end

local function open(path, server)
  vim.cmd.edit(vim.fn.fnameescape(root .. '/' .. path))
  local buf = vim.api.nvim_get_current_buf()
  local name = 'offline_' .. server
  local ok = vim.wait(timeout, function()
    local c = vim.lsp.get_clients({ bufnr = buf, name = name })[1]
    return c ~= nil and c.initialized
  end, 100)
  assert(ok, name .. ' 未附加到 ' .. path)
  local client = vim.lsp.get_clients({ bufnr = buf, name = name })[1]
  assert(vim.startswith(client.config.cmd[1], libexec),
    name .. ' 没有使用随包服务器: ' .. client.config.cmd[1])
  return buf, client
end

local function labels(result)
  local items = result and (result.items or result) or {}
  local out = {}
  for _, item in ipairs(items) do
    out[#out + 1] = (item.label:gsub('^"(.*)"$', '%1'))
  end
  return out
end

-- 服务器启动后可能还在建立项目索引，失败时重试直到超时。
local function expect_completion(buf, line, character, expected)
  local params = { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = line, character = character } }
  local seen = {}
  local ok = vim.wait(timeout, function()
    local responses = vim.lsp.buf_request_sync(buf, 'textDocument/completion', params, 10000) or {}
    for _, response in pairs(responses) do
      seen = labels(response.result)
      if vim.tbl_contains(seen, expected) then return true end
    end
    return false
  end, 500)
  assert(ok, ('缺少补全候选 %q，实际前 20 个: %s'):format(expected,
    table.concat(vim.list_slice(seen, 1, 20), ', ')))
end

local function expect_diagnostic(buf, pattern)
  local messages = {}
  local ok = vim.wait(timeout, function()
    messages = vim.tbl_map(function(d) return d.message end, vim.diagnostic.get(buf))
    for _, message in ipairs(messages) do
      if message:find(pattern) then return true end
    end
    return false
  end, 200)
  assert(ok, ('缺少匹配 %q 的诊断，实际: %s'):format(pattern, table.concat(messages, ' | ')))
end

local schema = {
  '{"$schema":"http://json-schema.org/draft-07/schema#","type":"object",',
  ' "properties":{"replicas":{"type":"integer","description":"副本数"},"image":{"type":"string"}},',
  ' "additionalProperties":false}',
}

-- Python：ty
write('py/pyproject.toml', { '[project]', 'name = "offline-test"', 'version = "0.1.0"' })
write('py/main.py', { 'import os', 'os.pa' })
write('py/bad.py', { 'count: int = "a"' })
local buf = open('py/main.py', 'python')
expect_completion(buf, 1, 5, 'path')
buf = open('py/bad.py', 'python')
expect_diagnostic(buf, '.')
print('PASS python ty: 标准库补全 os.path，类型错误诊断')

-- TypeScript/JavaScript：TypeScript 7，跨文件项目补全
write('ts/tsconfig.json', { '{"compilerOptions":{"strict":true,"allowJs":true}}' })
write('ts/a.ts', { 'export function helloOffline(): string { return "x"; }' })
write('ts/b.ts', { 'import { helloOffline } from "./a";', 'const s = "x";', 's.toUpp', 'helloOff' })
write('ts/c.ts', { 'const n: number = "a";' })
write('ts/d.js', { 'const arr = [1];', 'arr.pu' })
buf = open('ts/b.ts', 'typescript')
expect_completion(buf, 2, 7, 'toUpperCase')
expect_completion(buf, 3, 8, 'helloOffline')
buf = open('ts/c.ts', 'typescript')
expect_diagnostic(buf, 'number')
buf = open('ts/d.js', 'typescript')
expect_completion(buf, 1, 6, 'push')
print('PASS typescript tsc --lsp: 内置类型、跨文件导出、JS 补全，类型错误诊断')

-- YAML：文件头指定本地 schema
write('yaml/schema.json', schema)
write('yaml/app.yaml', { '# yaml-language-server: $schema=./schema.json', 'rep' })
write('yaml/bad.yaml', { '# yaml-language-server: $schema=./schema.json', 'replicas: abc' })
write('yaml/syntax.yaml', { 'a: [1, 2' })
buf = open('yaml/app.yaml', 'yaml')
expect_completion(buf, 1, 3, 'replicas')
buf = open('yaml/bad.yaml', 'yaml')
expect_diagnostic(buf, '[Ii]nteger')
buf = open('yaml/syntax.yaml', 'yaml')
expect_diagnostic(buf, '.')
print('PASS yaml-language-server: 本地 schema 键名补全和类型校验，语法错误诊断')

-- 自动模式下词库是否让位：用当前行前缀判断，> = 0 表示词库会给出候选。
local function keyword_start(buf, line, col)
  vim.api.nvim_win_set_cursor(0, { line + 1, col })
  return OfflineKeywordComplete(1, '')
end

-- Compose：随包官方 schema，无文件头，按文件名自动关联。
write('compose/compose.yaml', { 'services:', '  web:', '    ima' })
write('compose/compose.top.yaml', { 'services: {}', 'co' })
write('compose/compose.enum.yaml', { 'services:', '  web:', '    image: nginx', '    cgroup: ' })
write('compose/compose.bad.yaml', { 'servics:', '  web: {}' })
write('compose/docker-compose.prod.yml', { 'services:', '  web:', '    ima' })
write('compose/other.yaml', { 'services:', '  web:', '    ima' })
buf = open('compose/compose.yaml', 'yaml')
expect_completion(buf, 2, 7, 'image')
assert(keyword_start(buf, 2, 7) == -2, 'yaml 服务器附加后 compose 词库仍给出候选')
vim.b.offline_completion = 'compose'
assert(keyword_start(buf, 2, 7) >= 0, '手动选择 compose 词库后没有候选')
vim.b.offline_completion = nil
buf = open('compose/compose.top.yaml', 'yaml')
-- 已写出的 services 不再提示；include 只在顶层存在。
expect_completion(buf, 1, 2, 'include')
local top = vim.lsp.buf_request_sync(buf, 'textDocument/completion',
  { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = 1, character = 2 } }, 10000)
for _, response in pairs(top or {}) do
  assert(not vim.tbl_contains(labels(response.result), 'container_name'), '顶层出现了服务级字段 container_name')
end
buf = open('compose/compose.enum.yaml', 'yaml')
-- 服务下只有 cgroup 一个键时 yaml-language-server 不给值候选，这里放在已有 image 之后。
expect_completion(buf, 3, 12, 'host')
buf = open('compose/compose.bad.yaml', 'yaml')
expect_diagnostic(buf, 'servics')
buf = open('compose/docker-compose.prod.yml', 'yaml')
expect_completion(buf, 2, 7, 'image')
buf = open('compose/other.yaml', 'yaml')
local other = vim.lsp.buf_request_sync(buf, 'textDocument/completion',
  { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = 2, character = 7 } }, 10000)
for _, response in pairs(other or {}) do
  assert(not vim.tbl_contains(labels(response.result), 'image'), '非 Compose 文件名也关联了 Compose schema')
end
print('PASS yaml-language-server + Compose schema: 按层级补全、枚举值、未知字段诊断、文件名匹配、词库让位')

-- opencode：不关联 schema（其 schema 引用外部 models.dev），json 服务器附加后仍由词库补全。
write('opencode/opencode.json', { '{', '  "prov",', '  "share": 123', '}' })
buf = open('opencode/opencode.json', 'json')
expect_diagnostic(buf, '.')
assert(keyword_start(buf, 1, 6) >= 0, 'json 服务器附加后 opencode 词库没有候选')
for _, d in ipairs(vim.diagnostic.get(buf)) do
  assert(not d.message:find('schema'), 'opencode 文件出现 schema 相关诊断: ' .. d.message)
end
print('PASS opencode: json 服务器只做语法诊断，不加载 schema，词库照常补全')

-- JSON：$schema 指向本地文件
write('json/schema.json', schema)
write('json/app.json', { '{', '  "$schema": "./schema.json",', '  ""', '}' })
write('json/bad.json', { '{', '  "$schema": "./schema.json",', '  "replicas": "x"', '}' })
write('json/syntax.json', { '{"a": }' })
buf = open('json/app.json', 'json')
expect_completion(buf, 2, 3, 'image')
buf = open('json/bad.json', 'json')
expect_diagnostic(buf, '[Ii]nteger')
buf = open('json/syntax.json', 'json')
expect_diagnostic(buf, '.')
print('PASS vscode-json-language-server: 本地 schema 键名补全和类型校验，语法错误诊断')

-- Bash：文件内变量
write('sh/script.sh', { '#!/bin/bash', 'OFFLINE_VAR=1', 'echo "$OFFL"' })
buf = open('sh/script.sh', 'bash')
expect_completion(buf, 2, 11, 'OFFLINE_VAR')
print('PASS bash-language-server: 文件内变量补全')

for _, client in ipairs(vim.lsp.get_clients()) do client:stop() end
vim.wait(5000, function() return #vim.lsp.get_clients() == 0 end, 100)
vim.fn.writefile({ 'ok' }, assert(vim.env.TEST_ROOT) .. '/lsp-bundled.ok')
vim.cmd('qa!')
