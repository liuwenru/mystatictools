-- Synchronous checks also run in scratch, with no external commands or network.
assert(OfflineKeywordComplete, 'keyword completion module not loaded')
local root = assert(vim.env.TEST_ROOT) .. '/keywords'
vim.fn.mkdir(root, 'p')
local function buffer(name, ft)
  vim.cmd('enew!')
  vim.api.nvim_buf_set_name(0, root .. '/' .. name)
  if ft then vim.bo.filetype = ft else vim.cmd('filetype detect') end
end
local function candidates(before)
  local lines = vim.split(before, '\n', {plain = true})
  local last = lines[#lines]
  lines[#lines] = last .. ' '
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, {#lines, #last})
  local start = OfflineKeywordComplete(1, '')
  if start < 0 then return {} end
  return OfflineKeywordComplete(0, last:sub(start + 1)).words
end
local function find(items, word)
  for _, item in ipairs(items) do if item.word == word then return item end end
end
buffer('opencode.jsonc', 'jsonc')
assert(find(candidates('  "prov'), 'providers'))
assert(find(candidates('{ "per'), 'permissions'))
local provider = find(candidates('  "prov'), 'provider')
-- provider is still valid below websearch; only the deprecated root location is excluded.
assert(not provider or not provider.info:find('位置：$\n', 1, true), 'deprecated root location leaked')
assert(#candidates('  "model": "prov') == 0, 'keyword hints offered inside JSON string value')
buffer('compose.override.yaml', 'yaml')
assert(find(candidates('    ima'), 'image'))
assert(find(candidates('    hea'), 'healthcheck'))
assert(not find(candidates('ver'), 'version'), 'deprecated Compose version leaked')
assert(#candidates('    image: nginx') == 0 and #candidates('# ima') == 0)
buffer('ordinary.yaml', 'yaml')
assert(#candidates('ima') == 0, 'Compose hints leaked into ordinary YAML')
vim.cmd('OfflineCompletion compose')
assert(find(candidates('ima'), 'image'))
vim.cmd('OfflineCompletion off')
assert(#candidates('ima') == 0)
vim.cmd('OfflineCompletion auto')
assert(#candidates('ima') == 0)
buffer('nginx.conf', 'nginx')
local proxy = assert(find(candidates('  proxy_'), 'proxy_pass'))
assert(proxy.info:find('ngx_http_proxy_module', 1, true) and proxy.info:find('ngx_stream_proxy_module', 1, true))
assert(proxy.info:find('反向代理', 1, true), 'custom Chinese description missing')
assert(find(candidates('location / { proxy_'), 'proxy_pass'))
assert(#candidates('  proxy_pass ./') == 0 and #candidates('  # proxy_') == 0)
assert(#candidates('  proxy_pass http') == 0, 'directive hints offered in arguments')
buffer('example@.service')
assert(vim.bo.filetype == 'systemd')
assert(find(candidates('ExecSt'), 'ExecStart'))
assert(find(candidates('[Ser'), '[Service]'))
assert(find(candidates('Wanted'), 'WantedBy').info:find('Install', 1, true))
assert(find(candidates('MemoryM'), 'MemoryMax'))
assert(#candidates('ExecStart=') == 0 and #candidates('; ExecSt') == 0)
buffer('example.service.d/override.conf')
assert(vim.bo.filetype == 'systemd')
assert(find(candidates('LimitNO'), 'LimitNOFILE'))
buffer('ordinary.conf', 'conf')
assert(#candidates('ExecSt') == 0)
buffer('server.xml', 'xml')
assert(find(candidates('<Con'), 'Connector'))
assert(find(candidates('</Con'), 'Connector'), 'closing tag was mistaken for an absolute path')
assert(not find(candidates('<Con'), 'connectionTimeout'), 'attributes offered as element names')
local threads = assert(find(candidates('<Connector maxT'), 'maxThreads'))
assert(threads.info:find('Tomcat 9.0.123', 1, true) and threads.info:find('Tomcat 10.1.61', 1, true))
assert(not find(candidates('<Connector Con'), 'Connector'), 'element offered as an attribute')
assert(find(candidates('<Connector\n  socket.rx'), 'socket.rxBufSize'))
assert(find(candidates('<Connector port="8080" maxT'), 'maxThreads'))
assert(#candidates('<Connector protocol="maxT') == 0)
assert(#candidates('<!-- <Con') == 0 and #candidates('<![CDATA[<Con') == 0)
assert(#candidates('<!-- <Con\n maxT') == 0 and #candidates('outside maxT') == 0)
assert(#candidates('<Connector path="./') == 0, 'Tomcat dictionary competed with paths')
buffer('ordinary.xml', 'xml')
assert(#candidates('<Con') == 0, 'Tomcat hints leaked into unrelated XML')
vim.cmd('OfflineCompletion tomcat')
assert(find(candidates('<Con'), 'Connector'))
buffer('redis.conf', 'conf')
assert(find(candidates('maxm'), 'maxmemory'))
assert(find(candidates('append'), 'appendonly'))
assert(find(candidates('require'), 'requirepass').info:find('密码', 1, true))
assert(#candidates('# maxm') == 0 and #candidates('maxmemory 1') == 0)
buffer('ordinary-redis.conf', 'conf')
assert(#candidates('maxm') == 0, 'Redis hints leaked into unrelated conf')
vim.cmd('OfflineCompletion redis')
assert(find(candidates('maxm'), 'maxmemory'))
buffer('docker-start.sh', 'sh')
for _, command in ipairs({'dockerd', '/usr/bin/dockerd', 'sudo dockerd', 'exec dockerd', 'sudo exec dockerd'}) do
  assert(find(candidates(command .. ' --data-r'), '--data-root'), command)
end
assert(find(candidates('dockerd -H'), '-H'))
local level = assert(find(candidates('dockerd --log-l'), '--log-level'))
assert(level.info:find('本机帮助默认值："info"', 1, true))
assert(level.info:find('可选值：debug', 1, true))
for _, text in ipairs({'echo --data-r', '# dockerd --data-r', 'dockerd "--data-r',
  'dockerd --data-root=/tmp', 'dockerd --data-root /tmp', 'dockerd | cat --data-r',
  'dockerd > file --data-r', 'dockerd $(echo hi) --data-r', 'dockerd \\ --data-r',
  'dockerd --log-level "--data-r'}) do
  assert(#candidates(text) == 0, text)
end
buffer('docker-example.txt', 'text')
assert(#candidates('dockerd --data-r') == 0)
vim.cmd('OfflineCompletion dockerd-cli')
assert(find(candidates('ExecStart=/usr/bin/dockerd --data-r'), '--data-root'))
buffer('daemon.json', 'json')
assert(find(candidates('  "hos'), 'hosts'))
assert(not find(candidates('  "hos'), 'host'))
assert(find(candidates('  "log-op'), 'log-opts'))
assert(find(candidates('  "run'), 'runtimes'))
assert(find(candidates('  "http-p'), 'http-proxy').info:find('proxies', 1, true))
assert(find(candidates('  "bas'), 'base').info:find('default-address-pools[]', 1, true))
assert(#candidates('  "valida') == 0 and #candidates('  "config-f') == 0)
assert(#candidates('  "data-root": "hos') == 0)
buffer('daemon-example.json', 'json')
assert(#candidates('  "hos') == 0)
vim.cmd('OfflineCompletion docker-daemon')
assert(find(candidates('  "hos'), 'hosts'))
buffer('requests.http', 'http')
local header = assert(find(candidates('GET https://example.invalid/api HTTP/1.1\ncontent-t'), 'Content-Type'))
assert(header.icase == 1 and header.info:find('媒体类型', 1, true))
assert(header.info:find('Content-Type: <media-type>', 1, true))
assert(find(candidates('GET / HTTP/1.1\nHost: example.invalid\ncache-c'), 'Cache-Control'))
assert(find(candidates('GET / HTTP/1.1\n# comment\n// another comment\nAUTH'), 'Authorization'))
assert(find(candidates('HTTP/1.1 200 OK\nset-c'), 'Set-Cookie'))
for _, text in ipairs({'content-t', 'GET /content-t', '# content-t',
  'GET / HTTP/1.1\nContent-Type: content-t',
  'POST / HTTP/1.1\nContent-Type: text/plain\n\ncontent-t',
  'POST / HTTP/1.1\n\nGET /body HTTP/1.1\ncontent-t',
  'GET / HTTP/1.1\n\nHost: not-a-header\ncontent-t',
  'GET / HTTP/1.1\n< {% script %}\ncontent-t'}) do
  assert(#candidates(text) == 0, text)
end
assert(find(candidates('POST / HTTP/1.1\n\nbody\n### next\n@host = example.invalid\nGET /\ncontent-t'), 'Content-Type'))
buffer('requests.rest', 'text')
assert(find(candidates('GET /\nx-forwarded-f'), 'X-Forwarded-For').info:find('非标准', 1, true))
assert(#candidates('GET /\n:auth') == 0, 'pseudo-headers offered')
assert(#candidates('GET /\nx-xss') == 0 and #candidates('GET /\nno-vary-s') == 0)
assert(#candidates('GET /\npermissions-p') == 0, 'custom reintroduced an experimental MDN header')
buffer('headers-nginx.conf', 'nginx')
for _, directive in ipairs({'add_header', 'add_trailer', 'proxy_set_header', 'proxy_hide_header', 'proxy_pass_header'}) do
  assert(find(candidates(directive .. ' content-t'), 'Content-Type'), directive)
end
assert(find(candidates('location / { add_header "content-t'), 'Content-Type'))
assert(find(candidates("proxy_set_header 'x-forwarded-f"), 'X-Forwarded-For'))
assert(find(candidates('add_header X-Test "a;{}#b"; add_header content-t'), 'Content-Type'))
assert(find(candidates('proxy_pa'), 'proxy_pass'), 'ordinary nginx directive completion regressed')
for _, text in ipairs({'# add_header content-t', 'add_header Content-Type content-t',
  'set $var "add_header content-t', 'proxy_set_header Host "content-t',
  'add_header X-Test "a; add_header content-t', 'proxy_set_header Host $http_content_t',
  'add_header X-Test value; # add_header content-t'}) do
  assert(#candidates(text) == 0, text)
end
buffer('headers.json', 'json')
assert(#candidates('"content-t') == 0)
buffer('header-fragments.txt', 'text')
assert(#candidates('content-t') == 0)
vim.cmd('OfflineCompletion http-headers')
assert(find(candidates('CONTENT-T'), 'Content-Type'))
assert(#candidates('Content-Type: content-t') == 0)
vim.cmd('OfflineCompletion off')
assert(#candidates('content-t') == 0)
print('PASS nine keyword dictionaries, HTTP/REST header boundaries, Nginx header arguments and case-insensitive names')

-- Exercise manual add/override/disable/reload against an isolated copy, never user dictionaries.
local resources = vim.fn.fnamemodify(vim.uv.exepath(), ':h:h') .. '/completion'
local isolated = root .. '/isolated'
vim.fn.mkdir(isolated .. '/generated', 'p')
vim.fn.mkdir(isolated .. '/custom', 'p')
vim.fn.writefile(vim.fn.readfile(resources .. '/init.lua'), isolated .. '/init.lua')
vim.fn.writefile({vim.json.encode({entries = {
  {word = 'fixture_key', context = 'one', description = 'original'},
  {word = 'fixture_key', context = 'two', description = 'original'},
  {word = 'fixture_hidden', description = 'hidden'},
}})}, isolated .. '/generated/nginx.json')
vim.fn.writefile({vim.json.encode({
  {word = 'fixture_key', description = 'manual override'},
  {word = 'fixture_extra', description = 'manual addition'},
  {word = 'fixture_hidden', disabled = true},
})}, isolated .. '/custom/nginx.json')
dofile(isolated .. '/init.lua')
buffer('fixture.conf', 'nginx')
local items = candidates('fixture_')
assert(#items == 2 and not find(items, 'fixture_hidden'))
assert(find(items, 'fixture_key').info:find('manual override', 1, true))
vim.fn.writefile({'[{"word":"fixture_new","description":"reloaded"}]'}, isolated .. '/custom/nginx.json')
assert(not find(candidates('fixture_'), 'fixture_new'), 'cache changed without reload')
vim.cmd('OfflineCompletionReload')
assert(find(candidates('fixture_'), 'fixture_new'))
local notify = vim.notify
local warning
vim.notify = function(message) warning = message end
vim.fn.writefile({'{broken JSON'}, isolated .. '/custom/nginx.json')
vim.cmd('OfflineCompletionReload')
assert(find(candidates('fixture_'), 'fixture_key'), 'invalid custom file broke generated dictionary')
vim.wait(100, function() return warning and warning:find('加载失败', 1, true) ~= nil end, 10)
assert(warning and warning:find('加载失败', 1, true))
vim.notify = notify
dofile(resources .. '/init.lua')
vim.cmd('enew!')
print('PASS custom add/override/disable, reload and malformed custom fallback; user files unchanged')
