-- Offline keyword hints, not a parser or validator. Only reads this installation's files.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local cache = {}
local names = { "opencode", "compose", "nginx", "systemd-service", "tomcat", "redis", "dockerd-cli", "docker-daemon", "http-headers" }

local function nginx_header_token()
	local before = vim.api.nvim_get_current_line():sub(1, vim.fn.col(".") - 1)
	local start, quote = 1, nil
	for i = 1, #before do
		local char = before:sub(i, i)
		if char == "\\" then return end
		if quote then
			if char == quote then quote = nil end
		elseif char == '"' or char == "'" then
			quote = char
		elseif char == "#" then
			return
		elseif char:find("[;{}]") then
			start = i + 1
		end
	end
	local directive, token = before:sub(start):match("^%s*([%a_]+)%s+[\"']?([%a][%w-]*)$")
	if directive == "add_header" or directive == "add_trailer" or directive == "proxy_set_header"
		or directive == "proxy_hide_header" or directive == "proxy_pass_header" then return token end
end

local function http_header_token()
	if vim.bo.filetype == "nginx" then return nginx_header_token() end
	local before = vim.api.nvim_get_current_line():sub(1, vim.fn.col(".") - 1)
	local token = before:match("^%s*([%a][%w-]*)$")
	if not token then return end
	local path = vim.api.nvim_buf_get_name(0)
	if vim.bo.filetype ~= "http" and not path:match("%.http$") and not path:match("%.rest$") then
		return token -- Explicit selection also supports standalone header-name fragments.
	end
	-- REST-client text only: a request/status line, headers, blank line, then opaque body.
	-- A ### delimiter starts another request; never treat request-like body lines as headers.
	local state = "preamble"
	local methods = { GET = true, HEAD = true, POST = true, PUT = true, DELETE = true,
		PATCH = true, OPTIONS = true, CONNECT = true, TRACE = true }
	local row = vim.api.nvim_win_get_cursor(0)[1]
	for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, row - 1, false)) do
		if line:match("^%s*###") then
			state = "preamble"
		elseif state == "preamble" then
			local method, _, version = line:match("^%s*(%u+)%s+(%S+)%s*(.-)%s*$")
			if (methods[method] and (version == "" or version:match("^HTTP/%d%.%d$")))
				or line:match("^%s*HTTP/%d%.%d%s+%d%d%d") then state = "headers" end
		elseif state == "headers" then
			if line:match("^%s*$") then
				state = "body"
			elseif not line:match("^%s*#") and not line:match("^%s*//")
				and not line:match("^%s*[%w!#$%%&'*+%.%^_`|~%-]+%s*:") then
				state = "body" -- Unknown templates/scripts are not interpreted.
			end
		end
	end
	if state == "headers" then return token end
end

local function dockerd_option(require_command)
	local before = vim.api.nvim_get_current_line():sub(1, vim.fn.col(".") - 1)
	local quote
	for i = 1, #before do
		local char = before:sub(i, i)
		if char == "\\" then return end -- No shell escapes or line-continuation parsing.
		if quote then
			if char == quote then quote = nil end
		elseif char == '"' or char == "'" then
			quote = char
		elseif char:find("[;&|`$<>#]") then
			return -- Do not guess inside comments, substitutions, pipelines or redirects.
		end
	end
	if quote then return end
	local token = before:match("%s(%-%-?[%w-]*)$") or before:match("^%s*(%-%-?[%w-]*)$")
	if not token then return end
	if require_command then
		local words = {}
		for word in before:gmatch("%S+") do words[#words + 1] = word end
		local index = 1
		while words[index] == "sudo" or words[index] == "exec" do index = index + 1 end
		if not words[index] or vim.fs.basename(words[index]) ~= "dockerd" then return end
	end
	return token
end

local function dictionary_name()
	local selected = vim.b.offline_completion
	if selected and selected ~= "auto" then return selected ~= "off" and selected or nil end
	local path = vim.api.nvim_buf_get_name(0)
	local name = vim.fs.basename(path)
	if name:match("%.http$") or name:match("%.rest$") or vim.bo.filetype == "http" then return "http-headers" end
	if name == "daemon.json" then return "docker-daemon" end
	if name == "server.xml" then return "tomcat" end
	if name == "redis.conf" then return "redis" end
	if name == "opencode.json" or name == "opencode.jsonc" then return "opencode" end
	if name == "compose.yaml" or name == "compose.yml" or name == "docker-compose.yaml" or name == "docker-compose.yml"
		or name:match("^compose[%.%-].+%.ya?ml$") or name:match("^docker%-compose[%.%-].+%.ya?ml$") then
		return "compose"
	end
	if name:match("%.service$") or path:match("%.service%.d/[^/]+%.conf$") then return "systemd-service" end
	if vim.bo.filetype == "nginx" then return nginx_header_token() and "http-headers" or "nginx" end
	if (vim.bo.filetype == "sh" or vim.bo.filetype == "bash" or vim.bo.filetype == "zsh") and dockerd_option(true) then
		return "dockerd-cli"
	end
end

local function read_entries(path, optional)
	if optional and vim.fn.filereadable(path) == 0 then return {} end
	local ok, result = pcall(function()
		local data = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
		local entries = data.entries or data
		assert(vim.islist(entries), "应为 JSON 数组或含 entries 数组的对象")
		for _, entry in ipairs(entries) do
			assert(type(entry) == "table" and type(entry.word) == "string" and entry.word ~= ""
				and not entry.word:find("[%s%c]"), "word 应为不含空白的关键字")
			for _, key in ipairs({ "context", "description", "syntax", "module", "version", "source", "kind", "default" }) do
				assert(entry[key] == nil or type(entry[key]) == "string", key .. " 应为字符串")
			end
			assert(entry.kind == nil or entry.kind == "element" or entry.kind == "attribute", "kind 应为 element 或 attribute")
			assert(entry.disabled == nil or type(entry.disabled) == "boolean", "disabled 应为布尔值")
			for _, key in ipairs({ "values", "type" }) do
				if entry[key] then
					assert(vim.islist(entry[key]), key .. " 应为字符串数组")
					for _, value in ipairs(entry[key]) do assert(type(value) == "string", key .. " 应为字符串数组") end
				end
			end
		end
		return entries
	end)
	if not ok then
		vim.schedule(function() vim.notify("离线词库加载失败：" .. path .. "\n" .. tostring(result), vim.log.levels.WARN) end)
		return {}
	end
	return result
end

local function load_dictionary(name)
	if cache[name] then return cache[name] end
	local entries = read_entries(root .. "/generated/" .. name .. ".json", false)
	for _, custom in ipairs(read_entries(root .. "/custom/" .. name .. ".json", true)) do
		local matched = false
		for index, entry in ipairs(entries) do
			if entry.word == custom.word and (custom.context == nil or custom.context == entry.context) then
				entries[index] = vim.tbl_extend("force", entry, custom)
				matched = true
			end
		end
		if not matched then entries[#entries + 1] = custom end
	end
	local words = {}
	for _, entry in ipairs(entries) do
		if not entry.disabled then
			local item = words[entry.word]
			if not item then
				item = { word = entry.word, menu = "[" .. name .. "]", info = "", kind = entry.kind,
					icase = name == "http-headers" and 1 or 0, dup = 0 }
				words[entry.word] = item
			end
			local lines = {}
			for _, field in ipairs({ { "context", "位置" }, { "module", "模块" }, { "description", "说明" },
				{ "syntax", "语法" }, { "default", "本机帮助默认值" }, { "version", "版本" }, { "source", "参考" } }) do
				if entry[field[1]] and entry[field[1]] ~= "" then lines[#lines + 1] = field[2] .. "：" .. entry[field[1]] end
			end
			if entry.values and #entry.values > 0 then lines[#lines + 1] = "可选值：" .. table.concat(entry.values, ", ") end
			if entry.type and #entry.type > 0 then lines[#lines + 1] = "类型：" .. table.concat(entry.type, " / ") end
			item.info = item.info .. (item.info ~= "" and "\n\n" or "") .. table.concat(lines, "\n")
		end
	end
	local result = {}
	for _, item in pairs(words) do result[#result + 1] = item end
	table.sort(result, function(a, b) return a.word < b.word end)
	cache[name] = result
	return result
end

local function xml_context()
	-- Bounded lexical scan for a possibly incomplete tag, not XML tree/schema validation.
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local lines = vim.api.nvim_buf_get_lines(0, math.max(0, row - 200), row - 1, false)
	lines[#lines + 1] = vim.api.nvim_get_current_line():sub(1, vim.fn.col(".") - 1)
	local text = table.concat(lines, "\n")
	local quote, comment, cdata, opener
	local i = 1
	while i <= #text do
		local char = text:sub(i, i)
		if comment then
			if text:sub(i, i + 2) == "-->" then comment = false; i = i + 2 end
		elseif cdata then
			if text:sub(i, i + 2) == "]]>" then cdata = false; i = i + 2 end
		elseif quote then
			if char == quote then quote = nil end
		elseif text:sub(i, i + 3) == "<!--" then
			comment, opener, i = true, nil, i + 3
		elseif text:sub(i, i + 8) == "<![CDATA[" then
			cdata, opener, i = true, nil, i + 8
		elseif opener and (char == '"' or char == "'") then
			quote = char
		elseif char == "<" then
			opener = i
		elseif char == ">" then
			opener = nil
		end
		i = i + 1
	end
	if quote or comment or cdata or not opener then return end
	local tail = text:sub(opener + 1)
	local element = tail:match("^/?([%a_:][%w_.:-]*)$")
	if element then return element, "element" end
	if tail:match("^[%a_:][%w_.:-]*%s") then
		return tail:match("%s([%a_:][%w_.:-]*)$"), "attribute"
	end
end

_G.OfflineCompletionContext = dictionary_name

function _G.OfflineKeywordComplete(findstart, base)
	if vim.g.offline_completion_disabled then return findstart == 1 and -2 or {} end
	local name = dictionary_name()
	if not name or vim.bo.buftype ~= "" or OfflinePathComplete(1, "") >= 0 then
		return findstart == 1 and -2 or {}
	end
	local xml_word, xml_kind
	if name == "tomcat" then xml_word, xml_kind = xml_context() end
	if findstart == 1 then
		local before = vim.api.nvim_get_current_line():sub(1, vim.fn.col(".") - 1)
		local token
		if name == "http-headers" then
			token = http_header_token()
		elseif name == "dockerd-cli" then
			token = dockerd_option(false)
		elseif name == "tomcat" then
			token = xml_word
		elseif name == "redis" then
			token = before:match("^%s*([%a][%w_-]*)$")
		elseif name == "nginx" then
			token = (before:match("([^{};]*)$") or ""):match("^%s*([%w_]+)$")
		elseif name == "systemd-service" then
			token = before:match("^%s*([%a][%w]*)$") or before:match("^%s*(%[[%a]*)$")
		elseif name == "compose" then
			token = before:match("^%s*%-?%s*([%w_-]+)$")
		else
			-- Conservative line-local key detection; never inserts quotes, colons or values.
			local left, quoted = before:match('^(.-)"([%w_$-]+)$')
			if left and (left:match("^%s*$") or left:match("[,{]%s*$")) then token = quoted end
		end
		return token and (#before - #token) or -2
	end
	local words = {}
	for _, item in ipairs(load_dictionary(name)) do
		local prefix = item.word:sub(1, #base)
		local matches = name == "http-headers" and prefix:lower() == base:lower() or prefix == base
		if matches and (name ~= "tomcat" or (xml_word and (not item.kind or item.kind == xml_kind))) then
			words[#words + 1] = item
		end
	end
	return { words = words, refresh = "always" }
end

vim.opt.complete:prepend("Fv:lua.OfflineKeywordComplete")
vim.filetype.add({ extension = { service = "systemd" }, pattern = { [".*%.service%.d/[^/]+%.conf"] = "systemd" } })
vim.api.nvim_create_user_command("OfflineCompletion", function(opts)
	if not vim.tbl_contains(names, opts.args) and opts.args ~= "auto" and opts.args ~= "off" then
		vim.notify("未知离线词库：" .. opts.args, vim.log.levels.WARN)
		return
	end
	vim.b.offline_completion = opts.args
	vim.notify("当前缓冲区离线词库：" .. (dictionary_name() or "未匹配/关闭"))
end, {
	nargs = 1, force = true,
	complete = function() return vim.list_extend({ "auto", "off" }, vim.deepcopy(names)) end,
	desc = "选择当前缓冲区的离线词库，不改变文件类型",
})
vim.api.nvim_create_user_command("OfflineCompletionReload", function()
	cache = {}
	vim.notify("离线词库缓存已清空，下次补全重新读取")
end, { force = true, desc = "重新读取手工补录和生成词库" })
