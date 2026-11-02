-- The full test uses system Python; scratch exercises the missing-dependency path.
local conform = require('conform')
local root = vim.env.TEST_ROOT .. '/format'
vim.fn.mkdir(root, 'p')
vim.cmd('enew!')
vim.api.nvim_buf_set_name(0, root .. '/nginx.conf')
local original = {'server { location / { return 200; } }'}
vim.api.nvim_buf_set_lines(0, 0, -1, false, original)
vim.cmd('filetype detect')
assert(vim.bo.filetype == 'nginx' and vim.bo.syntax == 'nginx')
local notify = vim.notify
local message
vim.notify = function(text) message = text end
if vim.fn.executable('python3') == 1 then
  assert(#conform.list_formatters(0) == 1)
  -- Finish the input's undo block before invoking the formatter.
  vim.cmd('let &undolevels = &undolevels')
  vim.cmd('OfflineFormat')
  local expected = {'server {', '  location / {', '    return 200;', '  }', '', '}'}
  assert(vim.deep_equal(expected, vim.api.nvim_buf_get_lines(0, 0, -1, false)),
    'nginx unexpected output: ' .. vim.inspect(vim.api.nvim_buf_get_lines(0, 0, -1, false)) .. '; ' .. tostring(message))
  vim.cmd('undo')
  assert(vim.deep_equal(original, vim.api.nvim_buf_get_lines(0, 0, -1, false)),
    'nginx undo failed: ' .. vim.inspect(vim.api.nvim_buf_get_lines(0, 0, -1, false)))
  vim.cmd('OfflineFormat')
  vim.cmd('OfflineFormat')
  assert(vim.deep_equal(expected, vim.api.nvim_buf_get_lines(0, 0, -1, false)), 'nginx not idempotent')
  -- Cover comments, quoted delimiters, variables and a rewrite regex.
  local special = {
    'server {', '# 中文注释', 'set $message "hello; {world}";',
    'proxy_set_header Host ${host};', 'rewrite ^/old/(.*)$ /new/$1 permanent;', '}',
  }
  vim.api.nvim_buf_set_lines(0, 0, -1, false, special)
  vim.cmd('OfflineFormat')
  for index = 2, #special - 1 do
    assert(vim.api.nvim_buf_get_lines(0, index - 1, index, false)[1] == '  ' .. special[index])
  end
  -- Force a real Python process failure after emitting partial stdout.
  local args = conform.formatters.offline_nginxfmt.args
  conform.formatters.offline_nginxfmt.args = {'-c', 'import sys; print("PARTIAL"); sys.exit(1)'}
  local before = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local done, failure = false, nil
  conform.format({async = false, quiet = true}, function(err) failure, done = err, true end)
  assert(vim.wait(11000, function() return done end, 10))
  conform.formatters.offline_nginxfmt.args = args
  assert(failure and vim.deep_equal(before, vim.api.nvim_buf_get_lines(0, 0, -1, false)),
    'nginx failed process overwrote buffer')
  print('PASS nginx formatter, Unicode/quotes/variables/regex, undo, idempotence and process failure')
end
-- Also exercise missing Python on normal hosts, without changing the host PATH.
local path = vim.env.PATH
vim.env.PATH = root .. '/no-executables'
local before = vim.api.nvim_buf_get_lines(0, 0, -1, false)
vim.cmd('OfflineFormat')
vim.env.PATH = path
vim.notify = notify
assert(message and message:find('需要系统 python3', 1, true), 'missing Python warning not shown')
assert(vim.deep_equal(before, vim.api.nvim_buf_get_lines(0, 0, -1, false)))
assert(vim.fn.filereadable(root .. '/nginx.conf') == 0, 'nginx formatting saved the file')
print('PASS nginx missing Python warning and unchanged, unsaved buffer')
