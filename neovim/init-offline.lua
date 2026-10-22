-- 可选配置，不自动覆盖用户配置；不联网安装任何插件。
-- 本地目录浏览使用 nvim-tree；此配置不启用 netrw 的远程文件功能。
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.opt.number = true
-- 默认把鼠标选择/右键交还终端；需要编辑器鼠标时按 <leader>m。
vim.opt.mouse = ""
vim.opt.termguicolors = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.cmd("filetype plugin indent on")
vim.cmd("syntax enable")
vim.cmd("packadd onedark.nvim")
require("onedark").setup({ style = "dark" })
require("onedark").load()
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
require("ibl").setup({ indent = { char = "│" }, scope = { enabled = false } })
vim.cmd("packadd mini.align")
require("mini.align").setup() -- 可视选择后 gA，s 输入分隔符，Enter 确认预览。

vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("OfflineIndent", { clear = true }),
	pattern = { "sh", "json", "yaml", "xml", "nginx", "python" },
	callback = function(event)
		local width = vim.bo[event.buf].filetype == "python" and 4 or 2
		vim.bo[event.buf].expandtab = true
		vim.bo[event.buf].shiftwidth = width
		vim.bo[event.buf].softtabstop = width
	end,
})

-- 程序路径由当前 nvim 定位；不依赖目标机 PATH、Python 或 Node。
local tools = vim.fn.fnamemodify(vim.uv.exepath(), ":h:h") .. "/libexec/"
vim.cmd("packadd conform.nvim")
require("conform").setup({
	default_format_opts = { timeout_ms = 10000, lsp_format = "never" },
	formatters_by_ft = {
		sh = { "offline_shfmt" },
		json = { "offline_jq" },
		yaml = { "offline_yamlfmt" },
		python = { "offline_ruff" },
		xml = { "offline_xmllint" },
	},
	formatters = {
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
	if vim.bo.filetype == "nginx" then
		local view = vim.fn.winsaveview()
		vim.cmd("normal! gg=G")
		vim.fn.winrestview(view)
		vim.notify("Nginx 仅重新缩进；配置有效性需另用 nginx -t 检查")
	elseif vim.bo.filetype == "jproperties" then
		vim.notify("properties 不自动改写；简单键值行可选择后使用 gA 手动对齐")
	elseif #require("conform").list_formatters(0) == 0 then
		vim.notify("此文件类型未配置离线格式化器", vim.log.levels.WARN)
	else
		require("conform").format({ async = false })
	end
end, { desc = "手动离线格式化，不保存文件", force = true })
vim.keymap.set("n", "<leader>f", "<cmd>OfflineFormat<CR>", { desc = "手动格式化/重新缩进" })

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
