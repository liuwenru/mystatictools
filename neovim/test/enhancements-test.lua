-- Same tests run with no shell, Python, Node, shared libraries or network in scratch.
assert(package.loaded.ibl and package.loaded.conform and MiniAlign)
dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h') .. '/keyword-test.lua')
dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h') .. '/help-controls-test.lua')
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
-- Two complete cycles catch RGB being re-enabled or plugin highlights left behind.
assert(vim.fn.maparg('\\c', 'n') == '<Cmd>OfflineColor<CR>' or
  vim.fn.maparg('\\c', 'n'):lower() == '<cmd>offlinecolor<cr>')
for _ = 1, 2 do
  vim.cmd('OfflineColor')
  assert(vim.g.colors_name == 'habamax' and not vim.o.termguicolors)
  assert(vim.api.nvim_get_hl(0, {name = 'Normal'}).ctermbg == 234)
  assert(require('ibl.config').get_config(0).enabled)
  assert(vim.api.nvim_get_hl(0, {name = 'OfflineIndent'}).ctermfg == 236)
  vim.cmd('OfflineColor')
  assert(vim.g.colors_name == 'vim' and not vim.o.termguicolors)
  assert(not require('ibl.config').get_config(0).enabled)
  local normal = vim.api.nvim_get_hl(0, {name = 'Normal'})
  assert(normal.bg == nil and normal.fg == nil and normal.ctermbg == nil and normal.ctermfg == nil,
    'ANSI retained previous Normal colors')
  for _, name in ipairs({'Comment', 'String', '@keyword', 'Directory', 'Search', 'Visual',
    'NvimTreeNormal', 'NvimTreeFolderName', 'NvimTreeRootFolder', 'NvimTreeCursorLine'}) do
    local hl = vim.api.nvim_get_hl(0, {name = name, link = false})
    for _, channel in ipairs({'ctermfg', 'ctermbg'}) do
      assert(hl[channel] == nil or hl[channel] < 16, name .. ': not ANSI 16 color')
    end
  end
  vim.cmd('OfflineColor')
  assert(vim.g.colors_name == 'onedark' and vim.o.termguicolors)
  assert(require('ibl.config').get_config(0).enabled)
  assert(vim.api.nvim_get_hl(0, {name = 'OfflineIndent'}).fg == 0x343a43)
end
vim.cmd('OfflineColor ansi')
vim.cmd('OfflineColor 256')
vim.cmd('OfflineColor truecolor')
assert(vim.g.colors_name == 'onedark' and vim.o.termguicolors)
print('PASS truecolor/256/ANSI cycles, explicit selection, faint guides and low-color plugin highlights')
-- Theme switches clear highlights; the cursor color and the stronger OneDark selection must come back.
-- cursorcolumn forces a full-window redraw per move; off by default, \l toggles it.
assert(vim.o.cursorline and not vim.o.cursorcolumn)
vim.api.nvim_feedkeys('\\l', 'x', false)
assert(vim.wo.cursorcolumn)
vim.api.nvim_feedkeys('\\l', 'x', false)
assert(not vim.wo.cursorcolumn)
assert(vim.o.guicursor:find('v:hor20-OfflineCursor', 1, true))
assert(vim.api.nvim_get_hl(0, {name = 'OfflineCursor'}).bg == 0xff3b30)
assert(vim.api.nvim_get_hl(0, {name = 'Visual', link = false}).bg == 0x3e5175)
assert(vim.api.nvim_get_hl(0, {name = 'CursorLine', link = false}).bg ~= 0x3e5175)
print('PASS red cursor, underline cursor in Visual, cursor line and \\l column toggle after theme cycles')
local color_file = vim.fn.stdpath('state') .. '/offline-color'
vim.cmd('OfflineColor ansi')
assert(vim.fn.readfile(color_file)[1] == 'ansi', 'color mode not saved')
vim.cmd('OfflineColor truecolor')
assert(vim.fn.readfile(color_file)[1] == 'truecolor', 'color mode not restored')
print('PASS color mode saved to state directory')
assert(vim.g.clipboard == nil and vim.o.clipboard == '' and vim.o.mouse == '')
assert(vim.g.termfeatures.osc52 == false)
local conform = require('conform')
local tools = vim.fn.fnamemodify(vim.uv.exepath(), ':h:h') .. '/libexec/'
for _, tool in ipairs({
  {'shfmt', '--version', 'v3.14.1'}, {'yamlfmt', '-version', '0.21.0'},
  {'ruff', '--version', 'ruff 0.17.1'}, {'jq', '--version', 'jq-1.8.2'},
  {'xmllint', '--version', '21504'},
  {'biome', '--version', '2.6.2'},
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

dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h') .. '/jsonc-format-test.lua')
dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h') .. '/nginx-format-test.lua')
-- Guide checks must work even in scratch, where Nginx cannot run without Python.
vim.api.nvim_buf_set_lines(0, 0, -1, false, {'server {', '  location / {', '    return 200;', '  }', '}'})
assert(require('ibl.config').get_config(0).scope.enabled == false)
require('ibl').refresh(0)
local namespace = vim.api.nvim_get_namespaces().indent_blankline
assert(namespace and #vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {}) > 0,
  'indent guides produced no virtual text')
local before_colors = vim.api.nvim_buf_get_lines(0, 0, -1, false)
vim.cmd('OfflineColor ansi')
require('ibl').refresh(0)
assert(#vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {}) == 0, 'ANSI left indent guides visible')
vim.cmd('OfflineColor truecolor')
require('ibl').refresh(0)
assert(#vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {}) > 0, 'RGB did not restore indent guides')
assert(vim.deep_equal(before_colors, vim.api.nvim_buf_get_lines(0, 0, -1, false)), 'color switch changed buffer')

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
print('PASS invalid input preservation, XML entities, nginx formatter/dependency, properties syntax/alignment')
