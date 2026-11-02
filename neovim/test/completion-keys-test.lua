-- Actual input-event tests for insert and colon command-line completion keys.
-- Called by completion-test.lua after the automatic source/LSP tests.
local root = assert(vim.env.TEST_ROOT) .. '/completion-keys'
vim.fn.mkdir(root, 'p')
vim.cmd('enew!')
vim.api.nvim_buf_set_name(0, root .. '/unsaved.txt')
vim.bo.filetype = 'text'
vim.bo.autocomplete = false -- Deterministic menus here; automatic sources are tested separately.
local source = vim.api.nvim_get_current_buf()
local wildoptions, wildmode = vim.o.wildoptions, vim.o.wildmode
local calls, argument, confirmed_command = 0, nil, nil
vim.api.nvim_create_user_command('OfflineKeyFixture', function(opts)
  calls, argument = calls + 1, opts.args
end, {nargs = '?', complete = function(lead)
  return lead == 'only' and {'only-one'} or {'alpha', 'beta', 'gamma'}
end})

local steps = {
  function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {'alpha alpine', 'al', 'tail'})
    vim.api.nvim_win_set_cursor(0, {2, 0})
    vim.cmd('startinsert!')
  end,
  function() vim.fn.complete(1, {'alpha', 'alpine'}) end,
  function()
    assert(vim.fn.pumvisible() == 1 and vim.fn.complete_info().selected == -1)
    vim.api.nvim_input('<Down>')
  end,
  function()
    assert(vim.fn.complete_info().selected == 0)
    vim.api.nvim_input('<Down>')
  end,
  function()
    assert(vim.fn.complete_info().selected == 1)
    vim.api.nvim_input('<Up>')
  end,
  function()
    assert(vim.fn.complete_info().selected == 0)
    vim.api.nvim_input('<CR>')
  end,
  function()
    assert(vim.fn.pumvisible() == 0 and vim.fn.mode() == 'i')
    assert(vim.api.nvim_buf_line_count(0) == 3 and vim.api.nvim_get_current_line() == 'alpha', 'insert Enter added a newline while confirming')
    vim.api.nvim_input('<Esc>')
  end,
  function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {'al', 'next'})
    vim.api.nvim_win_set_cursor(0, {1, 0})
    vim.cmd('startinsert!')
  end,
  function() vim.fn.complete(1, {'alpha', 'alpine'}) end,
  function()
    assert(vim.fn.complete_info().selected == -1)
    vim.api.nvim_input('<CR>')
  end,
  function()
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), {'al', '', 'next'}), 'unselected insert Enter did not make a normal newline: ' .. vim.inspect(vim.api.nvim_buf_get_lines(0, 0, -1, false)))
    vim.api.nvim_input('<Down>')
  end,
  function()
    assert(vim.api.nvim_win_get_cursor(0)[1] == 3)
    vim.api.nvim_input('<Up>')
  end,
  function()
    assert(vim.api.nvim_win_get_cursor(0)[1] == 2)
    vim.cmd('OfflineCompletionAll off')
    vim.api.nvim_input('<Down>')
  end,
  function()
    assert(vim.api.nvim_win_get_cursor(0)[1] == 3)
    vim.api.nvim_input('<Up>')
  end,
  function()
    assert(vim.api.nvim_win_get_cursor(0)[1] == 2)
    vim.api.nvim_input('<CR>')
  end,
  function()
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), {'al', '', '', 'next'}), 'total off changed normal Enter behavior')
    vim.api.nvim_input('<Esc>')
  end,
  function()
    vim.cmd('OfflineCompletionAll on')
    print('PASS insert Up/Down selection, selected Enter, unselected newline and total-off fallbacks')
  end,
}

-- Both native popup and horizontal wildmenu must select, confirm, then execute on a second Enter.
for _, options in ipairs({'pum,tagfile', 'tagfile'}) do
  local expected_calls = options == 'pum,tagfile' and 1 or 2
  steps[#steps + 1] = function()
    vim.o.wildoptions, vim.o.wildmode = options, 'full'
    vim.api.nvim_input(':OfflineKeyFixture <Tab>')
  end
  steps[#steps + 1] = function()
    assert(vim.fn.getcmdtype() == ':' and vim.fn.wildmenumode() == 1, 'Tab did not open command completion')
    assert(vim.fn.cmdcomplete_info().selected == 0)
    vim.api.nvim_input('<Down>')
  end
  steps[#steps + 1] = function()
    assert(vim.fn.cmdcomplete_info().selected == 1 and vim.fn.getcmdline():match('beta$'))
    vim.api.nvim_input('<Up>')
  end
  steps[#steps + 1] = function()
    assert(vim.fn.cmdcomplete_info().selected == 0 and vim.fn.getcmdline():match('alpha$'))
    vim.api.nvim_input('<Down><CR>')
  end
  steps[#steps + 1] = function()
    assert(vim.fn.getcmdtype() == ':' and vim.fn.wildmenumode() == 0)
    assert(calls == expected_calls - 1 and vim.fn.getcmdline():match('beta$'), 'first command Enter executed the command')
    vim.api.nvim_input('<CR>')
  end
  steps[#steps + 1] = function()
    assert(vim.fn.mode() == 'n' and calls == expected_calls and argument == 'beta', 'second command Enter did not execute')
  end
end
steps[#steps + 1] = function()
  vim.o.wildoptions, vim.o.wildmode = 'pum,tagfile', 'noselect:full'
  vim.api.nvim_input(':OfflineKeyFixture <Tab>')
end
steps[#steps + 1] = function()
  assert(vim.fn.wildmenumode() == 1 and vim.fn.cmdcomplete_info().selected == -1)
  vim.api.nvim_input('<CR>')
end
steps[#steps + 1] = function()
  assert(vim.fn.mode() == 'n' and calls == 3 and argument == '', 'unselected command Enter did not execute typed command normally')
  vim.fn.histadd('cmd', 'OfflineKeyFixture history-one')
  vim.fn.histadd('cmd', 'OfflineKeyFixture history-two')
  vim.api.nvim_input(':OfflineKeyFixture <Up>')
end
steps[#steps + 1] = function()
  assert(vim.fn.wildmenumode() == 0 and vim.fn.getcmdline() == 'OfflineKeyFixture history-two')
  vim.api.nvim_input('<Up>')
end
steps[#steps + 1] = function()
  assert(vim.fn.getcmdline() == 'OfflineKeyFixture history-one')
  vim.api.nvim_input('<Down>')
end
steps[#steps + 1] = function()
  assert(vim.fn.getcmdline() == 'OfflineKeyFixture history-two')
  vim.api.nvim_input('<CR>')
end
steps[#steps + 1] = function()
  assert(vim.fn.mode() == 'n' and calls == 4 and argument == 'history-two')
  vim.o.wildmode = 'full'
  vim.api.nvim_input(':OfflineKeyFixture only<Tab>')
end
steps[#steps + 1] = function()
  assert(vim.fn.wildmenumode() == 0 and vim.fn.getcmdline() == 'OfflineKeyFixture only-one')
  vim.api.nvim_input('<CR>')
end
steps[#steps + 1] = function()
  assert(vim.fn.mode() == 'n' and calls == 5 and argument == 'only-one', 'single-candidate command Enter did not execute normally')
  vim.cmd('OfflineCompletionAll off') -- Does not disable colon command completion.
  vim.o.wildmode = 'full'
  vim.api.nvim_input(':OfflineHelp <Tab><Down>')
end
steps[#steps + 1] = function()
  assert(vim.fn.getcmdtype() == ':' and vim.fn.wildmenumode() == 1)
  confirmed_command = vim.fn.getcmdline()
  vim.api.nvim_input('<CR>')
end
steps[#steps + 1] = function()
  assert(vim.fn.getcmdtype() == ':' and vim.fn.getcmdline() == confirmed_command)
  assert(vim.api.nvim_get_current_buf() == source, 'first Enter opened help before command execution')
  vim.api.nvim_input('<CR>')
end
steps[#steps + 1] = function()
  assert(vim.bo.filetype == 'help', 'second Enter did not execute OfflineHelp')
  vim.api.nvim_input('q')
end
steps[#steps + 1] = function()
  assert(vim.api.nvim_get_current_buf() == source)
  vim.cmd('OfflineCompletionAll on')
  vim.o.wildoptions, vim.o.wildmode = wildoptions, wildmode
  vim.api.nvim_del_user_command('OfflineKeyFixture')
  assert(vim.fn.filereadable(root .. '/unsaved.txt') == 0)
  print('PASS colon Tab, popup/horizontal Up/Down, two-step Enter, no-selection Enter, history and OfflineHelp while total off')
end

local index = 0
local function next_step()
  index = index + 1
  if not steps[index] then vim.cmd('qa!'); return end
  local ok, err = pcall(steps[index])
  if not ok then
    io.stderr:write('completion key step ' .. index .. ': ' .. tostring(err) .. '\n')
    vim.cmd('cquit 1')
    return
  end
  vim.defer_fn(next_step, 120)
end
vim.defer_fn(next_step, 80)
