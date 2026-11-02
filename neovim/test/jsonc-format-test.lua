-- Also runs in scratch: no Node, Python, shell, shared libraries or network.
local conform = require('conform')
local root = assert(vim.env.TEST_ROOT) .. '/jsonc'
vim.fn.mkdir(root, 'p')
-- A broken project configuration must not affect the bundled configuration.
vim.fn.writefile({'INVALID PROJECT CONFIG'}, root .. '/biome.json')
vim.fn.writefile({'INVALID PROJECT CONFIG'}, root .. '/biome.jsonc')
vim.fn.writefile({'[*]', 'indent_style = tab', 'indent_size = 8'}, root .. '/.editorconfig')
local input = {
  '{', '// 中文行注释', '"z":1, /* 块注释 */', '"a":[1,2,],',
  '"url":"https://example.invalid/a//b",', '"large":9007199254740993,',
  '"duplicate":1,', '"duplicate":2,', '}',
}
local path = vim.env.PATH
vim.env.PATH = root .. '/no-executables'
local cwd = vim.fn.getcwd()
vim.cmd.cd(root)
for _, name in ipairs({'settings.jsonc', 'custom.conf', 'settings.json'}) do
  vim.cmd('enew!')
  vim.api.nvim_buf_set_name(0, root .. '/' .. name)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, input)
  vim.cmd('filetype detect')
  if name == 'settings.jsonc' then
    assert(vim.bo.filetype == 'jsonc', 'jsonc extension not detected')
  else
    vim.bo.filetype = 'jsonc'
  end
  assert(vim.bo.syntax == 'jsonc' and vim.bo.shiftwidth == 2 and vim.bo.expandtab)
  local formatters = conform.list_formatters(0)
  assert(#formatters == 1 and formatters[1].name == 'offline_biome_jsonc')
  vim.cmd('let &undolevels = &undolevels')
  vim.cmd('OfflineFormat')
  local formatted = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local output = table.concat(formatted, '\n')
  for _, text in ipairs({'// 中文行注释', '/* 块注释 */', 'https://example.invalid/a//b',
    '9007199254740993', '"duplicate": 1', '"duplicate": 2'}) do
    assert(output:find(text, 1, true), 'lost comment/value: ' .. text .. '\n' .. output)
  end
  assert(output:find('\n  "z": 1', 1, true), 'not two-space indentation')
  assert(output:find('"z"', 1, true) < output:find('"a"', 1, true), 'keys reordered')
  assert(not output:find(',%s*[%]}]'), 'trailing comma not removed')
  assert(not output:find('\t', 1, true), 'project EditorConfig leaked into output')
  vim.cmd('undo')
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), input), 'undo failed')
  vim.cmd('OfflineFormat')
  vim.cmd('OfflineFormat')
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), formatted), 'not idempotent')
  assert(vim.fn.filereadable(root .. '/' .. name) == 0, 'formatter saved the file')
end
for _, invalid in ipairs({'{"broken":', '{/* unclosed', '{"a":1,,}', '{"a":"unterminated}'}) do
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {invalid})
  local done, failure = false, nil
  conform.format({async = false, quiet = true}, function(err) failure, done = err, true end)
  assert(vim.wait(11000, function() return done end, 10), 'format timeout')
  assert(failure, 'invalid JSONC accepted: ' .. invalid)
  assert(vim.api.nvim_get_current_line() == invalid, 'invalid input overwritten')
end
vim.env.PATH = path
vim.cmd.cd(cwd)
print('PASS JSONC comments, trailing commas, key/value preservation, isolated config, undo, idempotence and invalid input')
