-- 可选配置，不自动覆盖用户配置；不联网安装任何插件。
-- 本地目录浏览使用 nvim-tree；此配置不启用 netrw 的远程文件功能。
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.opt.number = true
-- 默认把鼠标选择/右键交还终端；需要编辑器鼠标时按 <leader>m。
vim.opt.mouse = ""
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.cmd("filetype plugin indent on")
vim.cmd("syntax enable")

-- Neovim 0.12 原生自动补全；只扫描当前正文，不读取其他缓冲区或 tags。
vim.opt.autocomplete = true
vim.opt.autocompletedelay = 150
vim.opt.completeopt = { "menu", "menuone", "noselect", "noinsert", "popup" }
vim.opt.complete = "Fv:lua.OfflinePathComplete,."
vim.g.offline_completion_disabled = false
-- 只在候选菜单中接管方向键；不修改 Tab，其他时候保留原生移动/历史。
for _, key in ipairs({ { "<Down>", "<C-n>" }, { "<Up>", "<C-p>" } }) do
	vim.keymap.set("i", key[1], function()
		return not vim.g.offline_completion_disabled and vim.fn.pumvisible() == 1 and key[2] or key[1]
	end, { expr = true, desc = "补全菜单中选择候选，否则正常移动" })
	vim.keymap.set("c", key[1], function()
		return vim.fn.getcmdtype() == ":" and vim.fn.wildmenumode() == 1 and key[2] or key[1]
	end, { expr = true, desc = "冒号补全菜单中选择候选，否则保留命令历史" })
end
vim.keymap.set("i", "<CR>", function()
	if vim.fn.pumvisible() == 1 then
		if not vim.g.offline_completion_disabled and vim.fn.complete_info({ "selected" }).selected >= 0 then return "<C-y>" end
		return "<C-e><CR>"
	end
	return "<CR>"
end, { expr = true, desc = "确认已选补全候选，否则正常换行" })
vim.keymap.set("c", "<CR>", function()
	if vim.fn.getcmdtype() == ":" and vim.fn.wildmenumode() == 1 then
		return (vim.fn.cmdcomplete_info().selected or -1) >= 0 and "<C-y>" or "<C-e><CR>"
	end
	return "<CR>"
end, { expr = true, desc = "确认已选命令候选但不执行，否则正常回车" })
-- 不通过 :cd/:lcd 改变目录，也不使用 glob 展开用户输入中的通配符。
function _G.OfflinePathComplete(findstart, base)
	if vim.g.offline_completion_disabled then return findstart == 1 and -2 or {} end
	if findstart == 1 then
		local before = vim.api.nvim_get_current_line():sub(1, vim.fn.col(".") - 1)
		local token = before:match("[^%s\"'`=;<>|{}()%[%],]+$") or ""
		-- XML 的 </Tag 是结束标签，不是从根目录开始的文件路径。
		local start = #before - #token
		if (vim.bo.filetype == "xml" or vim.b.offline_completion == "tomcat")
			and before:sub(start, start) == "<" and token:sub(1, 1) == "/" then return -2 end
		if token:match("^%./") or token:match("^%.%./") or token:match("^~/") or token:match("^/") then
			return #before - #token
		end
		return -2
	end
	-- 分开路径前缀和最后一级；前缀保持原样，只展开查找目录。
	local prefix, leaf = base:match("^(.*/)([^/]*)$")
	if not prefix then return {} end
	local directory = prefix
	if directory:sub(1, 2) == "~/" then
		directory = vim.fn.expand("~") .. directory:sub(2)
	elseif directory:sub(1, 1) ~= "/" then
		local name = vim.api.nvim_buf_get_name(0)
		local parent = name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
		directory = parent .. "/" .. directory
	end
	local scan = vim.uv.fs_scandir(directory)
	local words = {}
	while scan do
		if vim.fn.complete_check() == 1 then break end
		local name, kind = vim.uv.fs_scandir_next(scan)
		if not name then break end
		if name:sub(1, #leaf) == leaf and (name:sub(1, 1) ~= "." or leaf:sub(1, 1) == ".") then
			if kind == "link" then
				local stat = vim.uv.fs_stat(directory .. name)
				kind = stat and stat.type or kind
			end
			local suffix = kind == "directory" and "/" or ""
			table.insert(words, { word = prefix .. name .. suffix, menu = "[路径]", icase = 0 })
		end
	end
	table.sort(words, function(a, b) return a.word < b.word end)
	return { words = words, refresh = "always" }
end

-- 仓库试用读取配置旁的词库；安装后从 nvim/completion 定位，不读取当前工作目录的 Lua。
local completion_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/completion"
if vim.fn.filereadable(completion_dir .. "/init.lua") == 0 then
	completion_dir = vim.fn.fnamemodify(vim.uv.exepath(), ":h:h") .. "/completion"
end
if vim.fn.filereadable(completion_dir .. "/init.lua") == 1 then dofile(completion_dir .. "/init.lua") end

function _G.OfflineLspComplete(findstart, base)
	if vim.g.offline_completion_disabled then return findstart == 1 and -2 or {} end
	-- LSP 的关键字起点可能在最后一个 / 后；混入完整路径候选会重复插入前缀。
	-- 路径上下文只交给上面的文件系统来源，保证相对路径基准一致。
	if OfflinePathComplete(1, "") >= 0 then return findstart == 1 and -2 or {} end
	if OfflineKeywordComplete then
		local start = OfflineKeywordComplete(1, "")
		local before = vim.api.nvim_get_current_line():sub(1, vim.fn.col(".") - 1)
		-- [Service] 和 $schema 等非关键字起点也不能与 LSP 的关键字起点混用。
		if start >= 0 and start ~= vim.fn.match(before, [[\k*$]]) then return findstart == 1 and -2 or {} end
	end
	return vim.lsp.omnifunc(findstart, base)
end

-- 会话级开关：保留逐缓冲区选项/按键，不卸载词库，不断开 LSP。
local completion_options = { "autocomplete", "complete", "omnifunc", "completefunc" }
local completion_paused = { autocomplete = false, complete = "", omnifunc = "", completefunc = "" }
local completion_keys = { "<C-n>", "<C-p>", "<C-x>" }
-- Consume whole Ctrl+x sequences too, so their second key cannot start another editing command.
for _, suffix in ipairs({ "<C-n>", "<C-p>", "<C-l>", "<C-k>", "<C-t>", "<C-i>", "<C-]>", "<C-f>",
	"<C-d>", "<C-v>", "<C-u>", "<C-o>", "<C-s>", "s", "<C-z>", "<C-e>", "<C-y>" }) do
	completion_keys[#completion_keys + 1] = "<C-x>" .. suffix
end
local completion_globals, completion_buffers = nil, {}
local completion_clients, completion_pending_lsp = {}, {}
local function completion_snapshot(buf)
	local scope = buf and { buf = buf, scope = "local" } or { scope = "global" }
	local values = {}
	for _, name in ipairs(completion_options) do
		local value = vim.api.nvim_get_option_value(name, scope)
		-- Help/ftplugins may use s: functions; preserve their original script context.
		if (name == "omnifunc" or name == "completefunc") and value:match("^s:") then
			local sid = vim.api.nvim_get_option_info2(name, scope).last_set_sid
			value = value:gsub("^s:", "<SNR>" .. sid .. "_")
		end
		values[name] = value
	end
	return values
end
local function pause_completion_buffer(buf)
	if not vim.api.nvim_buf_is_loaded(buf) then return end
	local saved = completion_buffers[buf]
	if not saved then
		saved = { options = completion_snapshot(buf), maps = {} }
		-- New buffers may copy the current buffer's paused boolean instead of inheriting it.
		if vim.g.offline_completion_disabled then
			if saved.options.autocomplete == false then saved.options.autocomplete = nil end
			for _, name in ipairs({ "complete", "omnifunc", "completefunc" }) do
				if saved.options[name] == "" then saved.options[name] = completion_globals[name] end
			end
		end
		vim.api.nvim_buf_call(buf, function()
			for _, key in ipairs(completion_keys) do
				local map = vim.fn.maparg(key, "i", false, true)
				if map.buffer == 1 then saved.maps[key] = map end
			end
		end)
		completion_buffers[buf] = saved
	end
	for _, name in ipairs(completion_options) do
		vim.api.nvim_set_option_value(name, completion_paused[name], { buf = buf, scope = "local" })
	end
	for _, key in ipairs(completion_keys) do
		vim.keymap.set("i", key, "<Nop>", { buffer = buf, desc = "OfflineCompletionAll：补全已关闭" })
	end
end
vim.api.nvim_create_autocmd({ "BufEnter", "FileType", "InsertEnter" }, {
	group = vim.api.nvim_create_augroup("OfflineCompletionAll", { clear = true }),
	callback = function(event)
		if vim.g.offline_completion_disabled then pause_completion_buffer(event.buf) end
	end,
})
vim.api.nvim_create_autocmd("BufWipeout", {
	group = "OfflineCompletionAll",
	callback = function(event)
		completion_buffers[event.buf], completion_clients[event.buf], completion_pending_lsp[event.buf] = nil, nil, nil
	end,
})
vim.api.nvim_create_autocmd("LspDetach", {
	group = "OfflineCompletionAll",
	callback = function(event)
		if completion_clients[event.buf] then completion_clients[event.buf][event.data.client_id] = nil end
	end,
})
vim.api.nvim_create_autocmd("CompleteChanged", {
	group = "OfflineCompletionAll",
	callback = function()
		-- An LSP response already in flight may arrive after off; cancel its late menu too.
		if vim.g.offline_completion_disabled and vim.fn.pumvisible() == 1 then
			vim.api.nvim_feedkeys(vim.keycode("<C-e>"), "n", false)
		end
	end,
})
vim.api.nvim_create_user_command("OfflineCompletionAll", function(opts)
	local action = opts.args
	if action == "" then
		vim.notify("会话补全总开关：" .. (vim.g.offline_completion_disabled and "off" or "on"))
		return
	end
	if action ~= "on" and action ~= "off" and action ~= "toggle" then
		vim.notify("用法：OfflineCompletionAll [on|off|toggle]", vim.log.levels.WARN)
		return
	end
	local disabled = action == "off" or (action == "toggle" and not vim.g.offline_completion_disabled)
	if disabled == vim.g.offline_completion_disabled then return end
	if disabled then
		completion_globals = completion_snapshot()
		-- Snapshot existing buffers before changing global defaults, including local false values.
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do pause_completion_buffer(buf) end
		vim.g.offline_completion_disabled = true
		for _, name in ipairs(completion_options) do vim.go[name] = completion_paused[name] end
		-- Sources/keys are blocked above. Keep native LSP bookkeeping until pending replies finish,
		-- otherwise Neovim's late response callback can refer to its already-deleted autocmd group.
		if vim.fn.pumvisible() == 1 then vim.api.nvim_feedkeys(vim.keycode("<C-e>"), "n", false) end
	else
		vim.g.offline_completion_disabled = false
		for _, name in ipairs(completion_options) do vim.go[name] = completion_globals[name] end
		for buf, saved in pairs(completion_buffers) do
			if vim.api.nvim_buf_is_valid(buf) then
				for _, name in ipairs(completion_options) do
					vim.api.nvim_set_option_value(name, saved.options[name], { buf = buf, scope = "local" })
				end
				vim.api.nvim_buf_call(buf, function()
					for _, key in ipairs(completion_keys) do
						local map = vim.fn.maparg(key, "i", false, true)
						if map.buffer == 1 and map.desc == "OfflineCompletionAll：补全已关闭" then
							vim.keymap.del("i", key, { buffer = buf })
							if saved.maps[key] then vim.fn.mapset("i", false, saved.maps[key]) end
						end
					end
				end)
			end
		end
		for buf, clients in pairs(completion_clients) do
			for id in pairs(clients) do
				local client = vim.lsp.get_client_by_id(id)
				if client and client.attached_buffers[buf] then
					vim.lsp.completion.enable(true, id, buf, { autotrigger = false })
					if completion_pending_lsp[buf] then
						vim.bo[buf].omnifunc = "v:lua.OfflineLspComplete"
						vim.api.nvim_buf_call(buf, function() vim.opt_local.complete:append("o") end)
					end
				end
			end
		end
		completion_globals, completion_buffers, completion_pending_lsp = nil, {}, {}
	end
	vim.notify("会话补全总开关：" .. (disabled and "off" or "on"))
end, {
	nargs = "?", force = true,
	complete = function() return { "on", "off", "toggle" } end,
	desc = "关闭/恢复当前会话全部补全；无参数查询状态",
})

-- 只接入已有可执行程序；不安装服务器、插件或项目依赖。
local servers = {
	nginx = { cmd = { "nginx-language-server" }, filetypes = { "nginx" } },
	bash = { cmd = { "bash-language-server", "start" }, filetypes = { "sh", "bash" } },
	python = { cmd = { "pyright-langserver", "--stdio" }, filetypes = { "python" } },
	lua = { cmd = { "lua-language-server" }, filetypes = { "lua" } },
	json = { cmd = { "vscode-json-language-server", "--stdio" }, filetypes = { "json", "jsonc" } },
	yaml = { cmd = { "yaml-language-server", "--stdio" }, filetypes = { "yaml" },
		settings = { yaml = { schemaStore = { enable = false } } } },
	clangd = { cmd = { "clangd" }, filetypes = { "c", "cpp" } },
}
for name, config in pairs(servers) do
	if vim.fn.executable(config.cmd[1]) == 1 then
		config.root_markers = { ".git" }
		-- 无项目标记的独立配置文件也可启用。
		config.workspace_required = false
		if name == "json" then
			config.init_options = { provideFormatter = false }
			config.settings = { json = { schemaDownload = { enable = false } } }
		end
		vim.lsp.config("offline_" .. name, config)
		vim.lsp.enable("offline_" .. name)
	end
end
vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("OfflineLsp", { clear = true }),
	callback = function(event)
		local client = vim.lsp.get_client_by_id(event.data.client_id)
		if client and client:supports_method("textDocument/completion") then
			completion_clients[event.buf] = completion_clients[event.buf] or {}
			completion_clients[event.buf][client.id] = true
			-- 自动补全统一从 complete 的 o 来源触发，不另开一套触发计时器。
			if vim.g.offline_completion_disabled then
				pause_completion_buffer(event.buf)
				completion_pending_lsp[event.buf] = true
			else
				vim.lsp.completion.enable(true, client.id, event.buf, { autotrigger = false })
				vim.bo[event.buf].omnifunc = "v:lua.OfflineLspComplete"
				vim.api.nvim_buf_call(event.buf, function() vim.opt_local.complete:append("o") end)
			end
		end
		vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = event.buf, desc = "LSP 跳转定义" })
	end,
})

vim.cmd("packadd onedark.nvim")
require("onedark").setup({ style = "dark" })
-- y/p 仅用内部寄存器，跨 SSH 复制粘贴由终端负责，不再强制 OSC 52。
vim.opt.clipboard = ""
vim.g.termfeatures = vim.tbl_extend("force", vim.g.termfeatures or {}, { osc52 = false })
vim.keymap.set("n", "<leader>m", function()
	vim.o.mouse = vim.o.mouse == "" and "a" or ""
	vim.notify(vim.o.mouse == "" and "鼠标交给终端" or "Neovim 鼠标已启用")
end, { desc = "切换 Neovim/终端鼠标" })

-- 放在 runtime 的原生 opt package 中，移动安装目录后仍可发现。
vim.cmd("packadd nvim-tree.lua")
require("nvim-tree").setup({
	disable_netrw = true,
	git = { enable = false },
	diagnostics = { enable = false },
	actions = { use_system_clipboard = false },
	renderer = {
		icons = {
			show = {
				file = false,
				folder = false,
				folder_arrow = false,
				git = false,
				modified = false,
				hidden = false,
				diagnostics = false,
				bookmarks = false,
			},
		},
	},
})
vim.keymap.set("n", "<leader>e", "<cmd>NvimTreeToggle<CR>", { desc = "开关文件树" })

vim.cmd("packadd indent-blankline.nvim")
-- 自定义高亮不跟随 Comment/Whitespace，避免缩进线像多出一列正文。
local hooks = require("ibl.hooks")
hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
	vim.api.nvim_set_hl(0, "OfflineIndent", { fg = "#343a43", ctermfg = 236, nocombine = true })
end)
require("ibl").setup({ indent = { char = "│", highlight = "OfflineIndent" }, scope = { enabled = false } })

-- 当前行底色提示；Visual 选区覆盖在底色之上。
vim.opt.cursorline = true
-- 当前列底色每移动一格都要重画整窗并重跑正则语法高亮，SSH 下明显卡顿；默认关闭，需要对齐时按 <leader>l。
vim.opt.cursorcolumn = false
vim.keymap.set("n", "<leader>l", function()
	vim.wo.cursorcolumn = not vim.wo.cursorcolumn
	vim.notify("当前列底色：" .. (vim.wo.cursorcolumn and "开启" or "关闭"))
end, { desc = "开关当前列底色" })
-- 普通/插入模式用红色光标；可视模式改为红色下划线，不遮住选区末尾字符。
-- 终端只在真彩色模式下接受光标颜色（OSC 12），256/ANSI 模式沿用终端自身光标颜色。
vim.opt.guicursor = "n-c-sm:block-OfflineCursor,i-ci-ve:ver25-OfflineCursor,v:hor20-OfflineCursor,"
	.. "r-cr-o:hor20-OfflineCursor,t:block-blinkon500-blinkoff500-TermCursor"
-- 切换主题会清空高亮，每次 ColorScheme 后重新设置。
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("OfflineCursor", { clear = true }),
	callback = function()
		vim.api.nvim_set_hl(0, "OfflineCursor", { bg = "#ff3b30" })
		-- onedark 的 Visual(#3b3f4c) 与当前行/列底色(#31353f) 几乎一样，选区加深为蓝灰。
		if vim.g.colors_name == "onedark" then
			vim.api.nvim_set_hl(0, "Visual", { bg = "#3e5175", ctermbg = 15, ctermfg = 0 })
		end
	end,
})

-- 不伪造 TERM，不写回个人配置；\c 的选择记在 state 目录，NVIM_OFFLINE_COLOR 仅临时覆盖。
local color_modes = { "truecolor", "256", "ansi" }
local color_mode = "truecolor"
local color_file = vim.fn.stdpath("state") .. "/offline-color"
local function apply_color_mode(mode)
	if not vim.tbl_contains(color_modes, mode) then
		vim.notify("颜色模式应为 truecolor、256 或 ansi：" .. mode, vim.log.levels.WARN)
		return false
	end
	color_mode = mode
	vim.opt.background = "dark"
	if mode == "truecolor" then
		require("onedark").load()
	else
		vim.opt.termguicolors = false
		-- habamax 自带 256 色；vim 使用基础 16 色，沿用终端默认背景。
		vim.cmd.colorscheme(mode == "256" and "habamax" or "vim")
		if mode == "ansi" then
			-- vim 主题中的具名浅色/灰色会被 Neovim 解析成扩展索引，显式降为基础色。
			local ansi_colors = { [81] = 12, [121] = 10, [159] = 14, [224] = 9, [225] = 13, [242] = 8, [248] = 7 }
			for name, hl in pairs(vim.api.nvim_get_hl(0, {})) do
				if ansi_colors[hl.ctermfg] or ansi_colors[hl.ctermbg] then
					hl.ctermfg = ansi_colors[hl.ctermfg] or hl.ctermfg
					hl.ctermbg = ansi_colors[hl.ctermbg] or hl.ctermbg
					vim.api.nvim_set_hl(0, name, hl)
				end
			end
		end
	end
	require("ibl").update({ enabled = mode ~= "ansi" })
	return true
end
local startup_color, color_source = vim.env.NVIM_OFFLINE_COLOR, "NVIM_OFFLINE_COLOR"
if not startup_color and vim.fn.filereadable(color_file) == 1 then
	startup_color, color_source = vim.fn.readfile(color_file, "", 1)[1] or "", color_file
end
startup_color = startup_color or "truecolor"
if not vim.tbl_contains(color_modes, startup_color) then
	vim.notify("无效的 " .. color_source .. "：" .. startup_color .. "；使用 truecolor", vim.log.levels.WARN)
	startup_color = "truecolor"
end
apply_color_mode(startup_color)
vim.api.nvim_create_user_command("OfflineColor", function(opts)
	local mode = opts.args
	if mode == "" then
		for index, value in ipairs(color_modes) do
			if value == color_mode then
				mode = color_modes[index % #color_modes + 1]
				break
			end
		end
	end
	if not apply_color_mode(mode) then return end
	local saved = pcall(function()
		vim.fn.mkdir(vim.fn.fnamemodify(color_file, ":h"), "p")
		assert(vim.fn.writefile({ color_mode }, color_file) == 0)
	end)
	vim.notify("颜色模式：" .. color_mode .. "（" .. vim.g.colors_name .. "），缩进线" .. (color_mode == "ansi" and "关闭" or "淡色")
		.. (saved and "，已记住" or "；未能保存到 " .. color_file))
end, {
	nargs = "?",
	complete = function() return color_modes end,
	desc = "轮换或指定终端颜色模式",
	force = true,
})
vim.keymap.set("n", "<leader>c", "<cmd>OfflineColor<CR>", { desc = "轮换真彩色/256色/ANSI配色" })
vim.cmd("packadd mini.align")
require("mini.align").setup() -- 可视选择后 gA，s 输入分隔符，Enter 确认预览。

vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("OfflineIndent", { clear = true }),
	pattern = { "sh", "json", "jsonc", "yaml", "xml", "nginx", "python" },
	callback = function(event)
		local width = vim.bo[event.buf].filetype == "python" and 4 or 2
		vim.bo[event.buf].expandtab = true
		vim.bo[event.buf].shiftwidth = width
		vim.bo[event.buf].softtabstop = width
	end,
})

-- 随包工具由当前 nvim 定位；仅 Nginx 格式化需要 PATH 中的系统 python3。
local tools = vim.fn.fnamemodify(vim.uv.exepath(), ":h:h") .. "/libexec/"
vim.cmd("packadd conform.nvim")
require("conform").setup({
	default_format_opts = { timeout_ms = 10000, lsp_format = "never" },
	formatters_by_ft = {
		sh = { "offline_shfmt" },
		json = { "offline_jq" },
		jsonc = { "offline_biome_jsonc" },
		yaml = { "offline_yamlfmt" },
		python = { "offline_ruff" },
		xml = { "offline_xmllint" },
		nginx = { "offline_nginxfmt" },
	},
	formatters = {
		offline_biome_jsonc = {
			command = tools .. "biome",
			-- 固定虚拟扩展名，兼容手动 :set filetype=jsonc 的 .json/.conf 文件。
			args = { "format", "--config-path=" .. tools .. "biome-jsonc.json", "--stdin-file-path=offline.jsonc" },
			stdin = true,
		},
		offline_nginxfmt = {
			command = "python3",
			args = { tools .. "nginxfmt.py", "--pipe", "--indent", "2", "--line-endings", "unix" },
			stdin = true,
		},
		offline_shfmt = { command = tools .. "shfmt", args = { "-i", "2", "-filename", "$FILENAME" }, stdin = true },
		offline_jq = { command = tools .. "jq", args = { "--indent", "2", "." }, stdin = true },
		offline_yamlfmt = { command = tools .. "yamlfmt", args = { "-formatter", "indent=2", "-" }, stdin = true },
		offline_ruff = {
			command = tools .. "ruff",
			args = { "format", "--isolated", "--no-cache", "--stdin-filename", "$FILENAME", "-" },
			stdin = true,
		},
		offline_xmllint = {
			command = tools .. "xmllint",
			args = { "--nonet", "--format", "-" },
			stdin = true,
			env = { XML_CATALOG_FILES = "", XMLLINT_INDENT = "  " },
		},
	},
})
vim.api.nvim_create_user_command("OfflineFormat", function()
	if vim.bo.filetype == "nginx" and vim.fn.executable("python3") ~= 1 then
		vim.notify("Nginx 格式化需要系统 python3；未修改正文", vim.log.levels.WARN)
	elseif vim.bo.filetype == "jproperties" then
		vim.notify("properties 不自动改写；简单键值行可选择后使用 gA 手动对齐")
	elseif #require("conform").list_formatters(0) == 0 then
		vim.notify("此文件类型未配置离线格式化器", vim.log.levels.WARN)
	else
		require("conform").format({ async = false })
	end
end, { desc = "手动离线格式化，不保存文件", force = true })
vim.keymap.set("n", "<leader>f", "<cmd>OfflineFormat<CR>", { desc = "手动格式化/重新缩进" })

-- 仓库直接试用时也可 :help；安装后文档位于随包 runtime/doc，无需现场生成 tags。
local config_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
if vim.fn.filereadable(config_root .. "/doc/offline.txt") == 1
	and not vim.tbl_contains(vim.opt.runtimepath:get(), config_root) then vim.opt.runtimepath:append(config_root) end
local help_topics = { "completion", "headers", "nginx", "format", "tree", "theme", "clipboard", "limits", "current" }
vim.api.nvim_create_user_command("OfflineHelp", function(opts)
	local topic = opts.args
	if topic ~= "" and not vim.tbl_contains(help_topics, topic) then
		vim.notify("未知帮助主题：" .. topic .. "；用 :OfflineHelp 查看目录", vim.log.levels.WARN)
		return
	end
	if topic == "current" then
		local context = OfflineCompletionContext and OfflineCompletionContext()
		local ft = vim.bo.filetype
		if ft == "nginx" then topic = "nginx"
		elseif context == "http-headers" then topic = "headers"
		elseif context then topic = "completion"
		elseif ft == "NvimTree" then topic = "tree"
		elseif vim.tbl_contains({ "sh", "json", "jsonc", "yaml", "python", "xml", "jproperties" }, ft) then topic = "format"
		else topic = "" end
	end
	vim.cmd.help(topic == "" and "offline" or "offline-" .. topic)
	vim.bo.readonly, vim.bo.modifiable = true, false
	vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = true, desc = "关闭离线帮助窗口" })
end, {
	nargs = "?", force = true, complete = function() return help_topics end,
	desc = "查看本离线包的使用说明；current 按当前文件推荐主题",
})

-- vim.opt.termguicolors = true
-- vim.opt.background = "light"
--
-- -- 默认主题，也可以换成其他已安装的主题名称
-- vim.cmd.colorscheme("ron")
--
-- -- 放在主题加载之后，避免被主题覆盖
-- vim.api.nvim_set_hl(0, "Normal", {
-- 	bg = "#FAF9F6",
-- 	fg = "#333333",
-- })
-- vim.api.nvim_set_hl(0, "Comment", { fg = "#D98888" })
-- vim.api.nvim_set_hl(0, "@comment", { fg = "#D98888" })
