-- Run with the repository init-offline.lua and a complete bundled runtime.
-- TEST_ROOT must point to an isolated, disposable directory.
local root = assert(vim.env.TEST_ROOT, 'TEST_ROOT is required') .. '/completion'
local test_dir = vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))
vim.fn.mkdir(root .. '/edited/subdir', 'p')
vim.fn.mkdir(root .. '/cwd', 'p')
vim.fn.writefile({'fixture'}, root .. '/edited/target.conf')
vim.fn.writefile({'fixture'}, root .. '/edited/.hidden')
vim.fn.writefile({'fixture'}, root .. '/edited/subdir/nested.conf')
vim.fn.writefile({'wrong directory'}, root .. '/cwd/wrong.conf')
vim.cmd.cd(root .. '/cwd')
vim.cmd.edit(root .. '/edited/nginx.conf')
assert(vim.bo.filetype == 'nginx')
local cwd = vim.fn.getcwd()
local function has_path(base, expected)
  for _, item in ipairs(OfflinePathComplete(0, base).words or {}) do
    if item.word == expected then return true end
  end
  return false
end
assert(has_path('./', './target.conf'))
assert(has_path('./', './subdir/'))
assert(has_path('./subdir/', './subdir/nested.conf'))
assert(has_path('../', '../edited/'))
assert(has_path(root .. '/edited/', root .. '/edited/target.conf'))
assert(not has_path('./', './wrong.conf'))
assert(not has_path('./', './.hidden'))
assert(has_path('./.', './.hidden'))
assert(#OfflinePathComplete(0, './missing/').words == 0)
assert(#OfflinePathComplete(0, './tar*').words == 0)
assert(vim.fn.getcwd() == cwd)
assert(vim.o.autocomplete and vim.o.completeopt:find('noselect', 1, true))
local tab = vim.fn.maparg('<Tab>', 'i', false, true)
assert((next(tab) == nil or tab.desc == 'vim.snippet.jump if active, otherwise <Tab>')
  and vim.fn.maparg('<CR>', 'i', false, true).desc == '确认已选补全候选，否则正常换行')
print('PASS relative/nested/absolute paths, directories, hidden files, missing paths and unchanged cwd')

local stages = {
  {text = './', expected = './target.conf'},
  {text = '"./subdir/', expected = './subdir/nested.conf'},
  {text = 'offli', expected = 'offline_unique_word'},
  {text = './tar', expected = './target.conf', accept = true},
  {text = 'proxy_pa', expected = 'proxy_pass', accept = true},
  {text = 'ima', expected = 'image', dictionary = 'compose', accept = true},
  {text = '"prov', expected = 'providers', dictionary = 'opencode', accept = true, accepted = '"providers'},
  {text = '"$sch', expected = '$schema', dictionary = 'opencode', accept = true, accepted = '"$schema'},
  {text = 'ExecSt', expected = 'ExecStart', dictionary = 'systemd-service', accept = true},
  {text = '[Ser', expected = '[Service]', dictionary = 'systemd-service', accept = true},
  {text = '<Con', expected = 'Connector', dictionary = 'tomcat', accept = true, accepted = '<Connector'},
  {text = '</Con', expected = 'Connector', dictionary = 'tomcat', accept = true, accepted = '</Connector'},
  {text = '<Connector maxT', expected = 'maxThreads', dictionary = 'tomcat', accept = true, accepted = '<Connector maxThreads'},
  {text = '<Connector socket.rx', expected = 'socket.rxBufSize', dictionary = 'tomcat', accept = true, accepted = '<Connector socket.rxBufSize'},
  {text = 'maxm', expected = 'maxmemory', dictionary = 'redis', accept = true},
  {text = 'dockerd --data-r', expected = '--data-root', dictionary = 'dockerd-cli', accept = true, accepted = 'dockerd --data-root'},
  {text = 'dockerd -H', expected = '-H', dictionary = 'dockerd-cli', accept = true, accepted = 'dockerd -H'},
  {text = '"hos', expected = 'hosts', dictionary = 'docker-daemon', accept = true, accepted = '"hosts'},
  {text = '"log-op', expected = 'log-opts', dictionary = 'docker-daemon', accept = true, accepted = '"log-opts'},
  -- Native completion preserves the case of the already-typed prefix; HTTP names ignore case.
  {text = 'add_header content-t', expected = 'Content-Type', accept = true, accepted = 'add_header content-Type'},
  {text = 'proxy_set_header "x-forwarded-f', expected = 'X-Forwarded-For', accept = true, accepted = 'proxy_set_header "x-forwarded-For'},
  {text = 'CONTENT-T', expected = 'Content-Type', dictionary = 'http-headers', filetype = 'text', accept = true, accepted = 'CONTENT-Type'},
  {text = 'content-t', expected = 'Content-Type', filetype = 'http', preceding = {'GET / HTTP/1.1'}, accept = true, accepted = 'content-Type'},
  {text = 'offli', expected = 'offline_unique_word', close_with_switch = true},
  {text = 'offli', control = 'off', none = true, keys = '<C-n><C-p>'},
  {text = './tar', none = true, keys = '<C-x><C-f>'},
  {text = 'proxy_pa', none = true, keys = '<C-x><C-u>'},
  {text = 'serv', none = true, keys = '<C-x><C-o>'},
  {text = 'offli', control = 'on', expected = 'offline_unique_word'},
  {text = './tar', expected = './target.conf', accept = true, arrows = true},
  {text = 'add_header content-t', expected = 'Content-Type', accept = true, arrows = true, accepted = 'add_header content-Type'},
}
local index = 0
local function next_stage()
  index = index + 1
  local stage = stages[index]
  if not stage then
    vim.cmd.stopinsert()
    assert(vim.fn.getcwd() == cwd)
    assert(vim.fn.filereadable(root .. '/edited/nginx.conf') == 0)
    print('PASS automatic menus, no preselection/insertion, accept/cancel, total off/manual-key suppression and restored completion')
    print('PASS completion menus do not implicitly save the edited file')
    vim.defer_fn(function()
      local ok, err = pcall(dofile, test_dir .. '/completion-keys-test.lua')
      if not ok then print(err); vim.cmd('cquit 1') end
    end, 80)
    return
  end
  vim.api.nvim_input(vim.keycode('<Esc>'))
  vim.defer_fn(function()
    vim.b.offline_completion = stage.dictionary or 'auto'
    vim.bo.filetype = stage.filetype or 'nginx'
    if stage.control then vim.cmd('OfflineCompletionAll ' .. stage.control) end
    local lines = vim.deepcopy(stage.preceding or {'offline_unique_word'})
    lines[#lines + 1] = ''
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, {#lines, 0})
    vim.cmd.startinsert()
    vim.defer_fn(function()
      vim.api.nvim_input((stage.text:gsub('<', '<LT>')))
      if stage.keys then
        vim.defer_fn(function() vim.api.nvim_input(vim.keycode(stage.keys)) end, 180)
      end
      if stage.request_then_off then
        vim.defer_fn(function()
          vim.lsp.completion.get()
          vim.cmd('OfflineCompletionAll off')
        end, 180)
      end
    end, 40)
  end, 40)
  vim.defer_fn(function()
    local ok, failure = pcall(function()
      local info = vim.fn.complete_info({'items', 'selected'})
      local found
      for position, item in ipairs(info.items) do
        if item.word == stage.expected then found = position end
      end
      if stage.none then
        assert(vim.fn.pumvisible() == 0, 'completion menu appeared while the total switch was off')
        assert(vim.api.nvim_get_current_line() == stage.text and vim.fn.mode() == 'i', 'disabled completion key changed the text/mode')
        return
      end
      assert(vim.fn.pumvisible() == 1 and found,
        'missing automatic candidate ' .. stage.expected .. ': ' .. vim.inspect(info)
          .. ' line=' .. vim.inspect(vim.api.nvim_get_current_line()) .. ' mode=' .. vim.fn.mode())
      assert(info.selected == -1, 'candidate was preselected')
      assert(vim.api.nvim_get_current_line() == stage.text, 'completion changed text')
      if stage.close_with_switch then
        vim.cmd('OfflineCompletionAll off')
      elseif stage.accept then
        local next_key = stage.arrows and '<Down>' or '<C-n>'
        local confirm_key = stage.arrows and '<CR>' or '<C-y>'
        vim.api.nvim_input(string.rep(next_key, found) .. confirm_key)
      else
        vim.api.nvim_input(vim.keycode('<C-e>'))
      end
    end)
    if not ok then
      io.stderr:write(tostring(failure) .. '\n')
      vim.cmd('cquit 1')
      return
    end
    vim.defer_fn(function()
      local expected = stage.accept and (stage.accepted or stage.expected) or stage.text
      if stage.close_with_switch then assert(vim.fn.pumvisible() == 0, 'total off did not cancel the visible menu') end
      if vim.api.nvim_get_current_line() ~= expected then
        io.stderr:write('accept/cancel expected ' .. expected .. ', got '
          .. vim.api.nvim_get_current_line() .. '\n')
        vim.cmd('cquit 1')
        return
      end
      next_stage()
    end, 80)
  end, 650)
end

if vim.env.TEST_LSP == '1' then
  -- An actual local protocol exchange verifies the native async completion source.
  local id
  vim.cmd('OfflineCompletionAll off') -- Completion-capable LSP attaches while the session is paused.
  if vim.env.TEST_AUTO_LSP == '1' then
    assert(vim.wait(5000, function()
      local clients = vim.lsp.get_clients({bufnr = 0, name = 'offline_nginx'})
      id = clients[1] and clients[1].id
      return id ~= nil
    end, 10), 'PATH server was not automatically enabled')
  else
    id = vim.lsp.start({
      name = 'completion_fixture',
      cmd = {'python3', test_dir .. '/completion-lsp-server.py'},
      root_dir = root,
    })
  end
  assert(id and vim.wait(5000, function()
    local client = vim.lsp.get_client_by_id(id)
    return client and client.initialized
  end, 10), 'fixture LSP failed to initialize')
  assert(vim.wait(1000, function() return vim.bo.omnifunc == '' end, 10))
  assert(vim.lsp.get_client_by_id(id).attached_buffers[vim.api.nvim_get_current_buf()], 'total off detached the LSP')
  assert(vim.fn.maparg('gd', 'n') ~= '', 'total off removed LSP navigation')
  vim.cmd('OfflineCompletionAll on')
  assert(vim.bo.complete:find('o', 1, true), 'LSP completion source missing')
  print('PASS LSP attachment while disabled, retained navigation/connection and completion restoration')
  print('PASS local LSP initialization and completion source attachment')
  stages[#stages + 1] = {text = 'serv', control = 'on', request_then_off = true, none = true}
  stages[#stages + 1] = {text = 'serv', control = 'on', expected = 'server_name', accept = true, arrows = true}
end
vim.defer_fn(next_stage, 50)
