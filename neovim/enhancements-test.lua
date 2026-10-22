-- Same tests run with no shell, Python, Node, shared libraries or network in scratch.
assert(package.loaded.ibl and package.loaded.conform and MiniAlign)
assert(package.loaded.onedark and vim.g.colors_name == 'onedark')
assert(vim.g.onedark_config.style == 'dark' and vim.o.termguicolors)
local palette = require('onedark.palette').dark
assert(vim.api.nvim_get_hl(0, {name = 'Normal', link = false}).bg == tonumber(palette.bg0:sub(2), 16))
for _, group in ipairs({'Comment', 'String', '@keyword', 'NvimTreeNormal', 'IblIndent'}) do
  assert(next(vim.api.nvim_get_hl(0, {name = group, link = false})), group .. ': missing highlight')
end
-- Switching away and back must reapply the bundled theme without downloads.
vim.cmd('colorscheme habamax')
require('onedark').load()
assert(vim.g.colors_name == 'onedark')
print('PASS OneDark dark palette, syntax/plugin highlights and theme reload')
assert(vim.g.clipboard == nil and vim.o.clipboard == '' and vim.o.mouse == '')
assert(vim.g.termfeatures.osc52 == false)
local conform = require('conform')
local tools = vim.fn.fnamemodify(vim.uv.exepath(), ':h:h') .. '/libexec/'
for _, tool in ipairs({
  {'shfmt', '--version', 'v3.14.1'}, {'yamlfmt', '-version', '0.21.0'},
  {'ruff', '--version', 'ruff 0.17.1'}, {'jq', '--version', 'jq-1.8.2'},
  {'xmllint', '--version', '21504'},
}) do
  local result = vim.system({tools .. tool[1], tool[2]}, {text = true}):wait(10000)
  assert(result.code == 0 and ((result.stdout or '') .. (result.stderr or '')):find(tool[3], 1, true),
    tool[1] .. ': version mismatch')
end
local root = vim.env.TEST_ROOT .. '/format'
vim.fn.mkdir(root, 'p')
local samples = {
  {name = 'test.sh', ft = 'sh', input = 'if true;then\necho hello\nfi', match = '\n  echo hello\n'},
  {name = 'test.json', ft = 'json', input = '{"a":1,"b":[2,3]}', match = '  "a": 1'},
  {name = 'test.yaml', ft = 'yaml', input = 'key:   value\nnested:\n    x: 1', match = 'nested:\n  x: 1'},
  {name = 'test.py', ft = 'python', input = 'value={"a":1,"b":[2,3]}', match = 'value = {"a": 1, "b": [2, 3]}'},
  {name = 'server.xml', ft = 'xml', input = '<Server><Service name="Catalina"><Connector port="8080"/></Service></Server>', match = '\n  <Service name="Catalina">\n'},
}
for _, sample in ipairs(samples) do
  vim.cmd('enew!')
  vim.api.nvim_buf_set_name(0, root .. '/' .. sample.name)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(sample.input, '\n', {plain = true}))
  vim.cmd('filetype detect')
  assert(vim.bo.filetype == sample.ft, sample.name .. ': ' .. vim.bo.filetype)
  assert(vim.bo.syntax == sample.ft, sample.name .. ': missing syntax')
  assert(#conform.list_formatters(0) == 1)
  local done, failure = false, nil
  conform.format({async = false, timeout_ms = 10000, quiet = true}, function(err)
    failure, done = err, true
  end)
  assert(vim.wait(11000, function() return done end, 10), sample.name .. ': formatter timeout')
  assert(not failure, sample.name .. ': ' .. tostring(failure))
  local output = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  assert(output:find(sample.match, 1, true), sample.name .. ': unexpected output: ' .. output)
  assert(vim.fn.filereadable(root .. '/' .. sample.name) == 0, 'format unexpectedly saved the file')
  print('PASS formatter ' .. sample.ft)
end

-- Invalid input must not replace the buffer with partial or empty output.
for ft, text in pairs({json = '{"broken":', yaml = 'key: [unclosed', python = 'def broken(:', xml = '<Server><Service></Server>', sh = 'if then'}) do
  vim.cmd('enew!')
  vim.bo.filetype = ft
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {text})
  local done, failure = false, nil
  conform.format({async = false, timeout_ms = 10000, quiet = true}, function(err)
    failure, done = err, true
  end)
  assert(vim.wait(11000, function() return done end, 10))
  assert(failure, ft .. ': invalid input unexpectedly accepted')
  assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == text, ft .. ': invalid input overwritten')
end

-- XML must not substitute file entities or fetch remote DTDs in the default configuration.
local secret = root .. '/entity-secret.txt'
vim.fn.writefile({'DO_NOT_EXPAND_THIS_ENTITY'}, secret)
vim.cmd('enew!')
vim.bo.filetype = 'xml'
local xml = '<!DOCTYPE Server [<!ENTITY secret SYSTEM "file://' .. secret .. '">]><Server>&secret;</Server>'
vim.api.nvim_buf_set_lines(0, 0, -1, false, {xml})
local done, failure = false, nil
conform.format({async = false, quiet = true}, function(err) failure, done = err, true end)
assert(vim.wait(11000, function() return done end, 10))
assert(not failure, tostring(failure))
local output = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
assert(output:find('&secret;', 1, true) and not output:find('DO_NOT_EXPAND_THIS_ENTITY', 1, true))

vim.cmd('enew!')
vim.api.nvim_buf_set_name(0, root .. '/nginx.conf')
vim.api.nvim_buf_set_lines(0, 0, -1, false, {'server {', 'location / {', 'return 200;', '}', '}'})
vim.cmd('filetype detect')
assert(vim.bo.filetype == 'nginx' and vim.bo.syntax == 'nginx')
vim.cmd('OfflineFormat')
assert(vim.api.nvim_buf_get_lines(0, 2, 3, false)[1] == '    return 200;')
assert(require('ibl.config').get_config(0).scope.enabled == false)
require('ibl').refresh(0)
local namespace = vim.api.nvim_get_namespaces().indent_blankline
assert(namespace and #vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {}) > 0,
  'indent guides produced no virtual text')

vim.cmd('enew!')
vim.api.nvim_buf_set_name(0, root .. '/application.properties')
vim.api.nvim_buf_set_lines(0, 0, -1, false, {'# Keep order and escapes', 'name=\\u4e2d\\u6587', 'other = value\\', '  continued'})
vim.cmd('filetype detect')
assert(vim.bo.filetype == 'jproperties' and vim.bo.syntax == 'jproperties')
local original = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
vim.cmd('OfflineFormat')
assert(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n') == original)
local aligned = MiniAlign.align_strings({'a=1', 'long=2'}, {split_pattern = '='})
assert(aligned[1]:find('=') == aligned[2]:find('='))
print('PASS invalid input preservation, XML entities, nginx indent, properties syntax/alignment')
