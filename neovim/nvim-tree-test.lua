-- Run only inside TEST_ROOT; exercise actual plugin actions, not replacement fs calls.
dofile(vim.env.VIMRUNTIME .. '/../../../examples/init.lua')
assert(vim.g.loaded_netrw == 1 and vim.g.loaded_netrwPlugin == 1)
local api = require('nvim-tree.api')
vim.cmd('help nvim-tree')
assert(vim.bo.filetype == 'help')
local root = vim.env.TEST_ROOT .. '/tree'
vim.fn.mkdir(root .. '/destination', 'p')
vim.cmd('enew!')
api.tree.open({path = root})
assert(vim.bo.filetype == 'NvimTree')

-- Cursor selection exercises directory discovery and the plugin's public find API.
local function select_node(path)
  api.tree.reload()
  api.tree.find_file({buf = path, open = true, focus = true})
  assert(vim.wait(3000, function()
    local node = api.tree.get_node_under_cursor()
    return node and node.absolute_path == path
  end, 20), 'nvim-tree could not select ' .. path)
end

local original_input = vim.ui.input
local original_select = vim.ui.select
local answer
vim.ui.input = function(_, callback)
  assert(answer, 'unexpected nvim-tree input prompt')
  callback(answer)
end
vim.ui.select = function(items, _, callback) callback(items[1], 1) end

-- Create through nvim-tree's prompt, then open and edit through its node action.
answer = root .. '/created.txt'
api.fs.create()
assert(vim.fn.filereadable(answer) == 1)
select_node(answer)
-- Headless tests cannot answer the interactive window picker.
api.node.open.no_window_picker()
assert(vim.api.nvim_buf_get_name(0) == answer)
vim.api.nvim_buf_set_lines(0, 0, -1, false, {'offline nvim-tree 中文'})
vim.cmd('write')

select_node(root .. '/created.txt')
answer = 'renamed.txt'
api.fs.rename()
assert(vim.fn.filereadable(root .. '/renamed.txt') == 1)
assert(vim.fn.filereadable(root .. '/created.txt') == 0)

select_node(root .. '/renamed.txt')
api.fs.copy.node()
select_node(root .. '/destination')
api.fs.paste()
local copied = root .. '/destination/renamed.txt'
assert(vim.wait(3000, function() return vim.fn.filereadable(copied) == 1 end, 20))
assert(vim.fn.readfile(copied)[1] == 'offline nvim-tree 中文')

select_node(copied)
answer = 'y'
api.fs.remove()
assert(vim.wait(3000, function() return vim.fn.filereadable(copied) == 0 end, 20))
assert(vim.fn.filereadable(root .. '/renamed.txt') == 1)
vim.ui.input = original_input
vim.ui.select = original_select
api.tree.close()
print('PASS nvim-tree: browse, create, open, rename, copy, delete')
