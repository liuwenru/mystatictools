-- Run with the bundled runtime in a network-disabled scratch container.
local root = assert(vim.env.TEST_ROOT) .. '/toml-format'
vim.fn.mkdir(root, 'p')
vim.cmd.cd(root)
vim.fn.writefile({'[schema]', 'enabled = false'}, root .. '/tombi.toml')

local tools = vim.fn.fnamemodify(vim.uv.exepath(), ':h:h') .. '/libexec/'
local version = vim.system({tools .. 'tombi', '--version'}, {text = true}):wait(10000)
assert(version.code == 0 and (version.stdout or ''):find('1.11.3', 1, true), 'Tombi version mismatch')

local file = root .. '/sample.toml'
local input = {'# 中文注释', '[server]', 'ports=[80,443]'}
assert(vim.fn.writefile(input, file) == 0)
vim.cmd.edit(file)
assert(vim.bo.filetype == 'toml', '.toml extension not detected')
vim.api.nvim_feedkeys('\\f', 'xt', false)
local formatted = vim.api.nvim_buf_get_lines(0, 0, -1, false)
for _, line in ipairs({'# 中文注释', '[server]', 'ports = [80, 443]'}) do
  assert(vim.tbl_contains(formatted, line), 'unexpected TOML output: ' .. vim.inspect(formatted))
end
assert(vim.deep_equal(vim.fn.readfile(file), input), 'formatter wrote the file')
vim.cmd.undo()
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), input), 'undo failed')
vim.cmd.OfflineFormat()
vim.cmd.OfflineFormat()
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), formatted), 'not idempotent')

local invalid = {'ports = [80,'}
vim.api.nvim_buf_set_lines(0, 0, -1, false, invalid)
local done, failure = false, nil
require('conform').format({async = false, quiet = true}, function(err)
  failure, done = err, true
end)
assert(vim.wait(11000, function() return done end, 10), 'Tombi format timeout')
assert(failure, 'invalid TOML accepted')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), invalid), 'invalid TOML overwritten')
print('PASS Tombi version, TOML filetype, manual formatting, no write, undo, idempotence and invalid input')
