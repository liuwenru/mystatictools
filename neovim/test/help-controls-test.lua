-- Synchronous checks, also run with no external tools in the isolated root.
assert(vim.fn.exists(':OfflineHelp') == 2 and vim.fn.exists(':OfflineCompletionAll') == 2)
local root = assert(vim.env.TEST_ROOT) .. '/help-controls'
vim.fn.mkdir(root, 'p')
vim.cmd('enew!')
vim.api.nvim_buf_set_name(0, root .. '/nginx.conf')
vim.bo.filetype = 'nginx'
vim.api.nvim_buf_set_lines(0, 0, -1, false, {'unsaved content'})
local source = vim.api.nvim_get_current_buf()
local cwd = vim.fn.getcwd()
local commands = vim.fn.getcompletion('OfflineHelp ', 'cmdline')
assert(vim.tbl_contains(commands, 'completion') and vim.tbl_contains(commands, 'current'))
assert(vim.tbl_contains(vim.fn.getcompletion('OfflineCompletionAll ', 'cmdline'), 'off'))
for _, topic in ipairs({'', 'completion', 'headers', 'nginx', 'format', 'tree', 'theme', 'clipboard', 'limits', 'current'}) do
  vim.cmd('OfflineHelp ' .. topic)
  assert(vim.bo.filetype == 'help' and vim.bo.buftype == 'help')
  assert(vim.bo.readonly and not vim.bo.modifiable)
  local expected = topic == '' and 'offline' or topic == 'current' and 'offline-nginx' or 'offline-' .. topic
  assert(vim.api.nvim_get_current_line():find('*' .. expected .. '*', 1, true), topic)
  assert(vim.fn.maparg('q', 'n'):lower() == '<cmd>close<cr>')
  vim.api.nvim_feedkeys('q', 'xt', false)
  assert(vim.api.nvim_get_current_buf() == source)
end
vim.cmd('help OfflineCompletionAll')
assert(vim.api.nvim_get_current_line():find('*OfflineCompletionAll*', 1, true))
vim.cmd.close()
vim.cmd('help insert')
assert(not vim.api.nvim_buf_get_name(0):match('/offline.txt$'), 'packaging replaced the native help tags')
vim.cmd.close()
local notify = vim.notify
local warning
vim.notify = function(message) warning = message end
vim.cmd('OfflineHelp invalid')
assert(warning and warning:find('未知帮助主题', 1, true))
assert(vim.api.nvim_get_current_buf() == source)
vim.notify = notify
assert(vim.fn.getcwd() == cwd and vim.bo[source].modified)
assert(vim.fn.filereadable(root .. '/nginx.conf') == 0)
assert(vim.api.nvim_buf_get_lines(source, 0, -1, false)[1] == 'unsaved content')
print('PASS offline help topics/current, tags, q, native help and untouched edit buffer')

local original = {}
for _, name in ipairs({'autocomplete', 'complete', 'omnifunc', 'completefunc'}) do
  original[name] = vim.api.nvim_get_option_value(name, {scope = 'local'})
end
local global_complete = vim.go.complete
local global_map = vim.fn.maparg('<C-p>', 'i', false, true)
vim.keymap.set('i', '<C-p>', 'GLOBAL_FIXTURE', {desc = 'global fixture'})
local callback = function() return 'LOCAL_FIXTURE' end
vim.keymap.set('i', '<C-n>', callback, {buffer = source, expr = true, desc = 'local fixture'})
vim.keymap.set('i', '<C-x><C-o>', callback, {buffer = source, expr = true, desc = 'long local fixture'})
vim.b.offline_completion = 'off'
vim.cmd('enew!')
vim.api.nvim_buf_set_name(0, root .. '/hidden.txt')
local hidden = vim.api.nvim_get_current_buf()
vim.bo.autocomplete = false -- This explicit false must not be lost on restore.
vim.bo.complete = '.'
vim.api.nvim_set_current_buf(source)
for _ = 1, 2 do
  vim.cmd('OfflineCompletionAll off')
  vim.cmd('OfflineCompletionAll off') -- Idempotent, do not replace the original snapshots.
  assert(vim.g.offline_completion_disabled and vim.go.complete == '')
  for _, buf in ipairs({source, hidden}) do
    assert(vim.api.nvim_get_option_value('autocomplete', {buf = buf}) == false)
    assert(vim.bo[buf].complete == '' and vim.bo[buf].omnifunc == '' and vim.bo[buf].completefunc == '')
  end
  assert(OfflinePathComplete(1, '') == -2 and next(OfflinePathComplete(0, './')) == nil)
  assert(OfflineKeywordComplete(1, '') == -2 and next(OfflineKeywordComplete(0, 'proxy')) == nil)
  assert(OfflineLspComplete(1, '') == -2 and next(OfflineLspComplete(0, 'serv')) == nil)
  assert(vim.fn.maparg('<C-n>', 'i'):lower() == '<nop>')
  assert(vim.fn.maparg('<C-p>', 'i'):lower() == '<nop>')
  assert(vim.fn.maparg('<C-x>', 'i'):lower() == '<nop>')
  assert(vim.fn.maparg('<C-x><C-o>', 'i'):lower() == '<nop>')
  vim.cmd('enew!')
  local created = vim.api.nvim_get_current_buf()
  vim.bo.filetype = 'json'
  assert(not vim.api.nvim_get_option_value('autocomplete', {buf = created}) and vim.bo.omnifunc == '')
  vim.cmd('OfflineCompletionReload')
  assert(vim.g.offline_completion_disabled, 'dictionary reload enabled completion')
  vim.cmd('OfflineHelp completion')
  assert(vim.bo.filetype == 'help', 'help unavailable while completion is disabled')
  vim.cmd.close()
  vim.cmd('bwipeout! ' .. created) -- No stale snapshots for deleted buffers.
  vim.cmd('enew!')
  local survivor = vim.api.nvim_get_current_buf()
  vim.bo.filetype = 'sh'
  assert(not vim.o.autocomplete and vim.o.complete == '')
  vim.api.nvim_set_current_buf(source)
  vim.cmd('OfflineCompletionAll') -- Query only, no toggle.
  assert(vim.g.offline_completion_disabled)
  vim.cmd('OfflineCompletionAll toggle')
  assert(not vim.g.offline_completion_disabled and vim.go.complete == global_complete)
  for name, value in pairs(original) do
    assert(vim.api.nvim_get_option_value(name, {scope = 'local'}) == value, name)
  end
  assert(vim.api.nvim_get_option_value('autocomplete', {scope = 'local'}) == original.autocomplete)
  assert(vim.bo[hidden].autocomplete == false and vim.bo[hidden].complete == '.')
  assert(vim.b.offline_completion == 'off', 'total on overrode the per-buffer dictionary switch')
  assert(vim.fn.maparg('<C-n>', 'i', false, true).callback == callback, 'local callback mapping not restored')
  assert(vim.fn.maparg('<C-x><C-o>', 'i', false, true).callback == callback, 'long callback mapping not restored')
  assert(vim.fn.maparg('<C-p>', 'i') == 'GLOBAL_FIXTURE', 'global fallback mapping not restored')
  vim.api.nvim_buf_call(survivor, function()
    assert(vim.o.autocomplete and vim.o.complete:find('OfflineKeywordComplete', 1, true), 'new buffer defaults not restored')
    assert(vim.fn.maparg('<C-x>', 'i') == '', 'new buffer completion keys still blocked')
  end)
  vim.cmd('bwipeout! ' .. survivor)
end
vim.cmd('OfflineCompletionAll on')
vim.keymap.del('i', '<C-n>', {buffer = source})
vim.keymap.del('i', '<C-x><C-o>', {buffer = source})
vim.keymap.del('i', '<C-p>')
if next(global_map) then vim.fn.mapset('i', false, global_map) end
vim.b.offline_completion = 'auto'
vim.cmd('enew!')
print('PASS session completion off/on/toggle/query, existing/new/deleted buffers and option/keymap restoration')
