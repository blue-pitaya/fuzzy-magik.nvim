local M = {}

---@class AppContext
---@field prompt_win integer
---@field prompt_buf integer
---@field results_win integer
---@field results_buf integer
---@field preview_win integer
---@field preview_buf integer
---@field current_results ListItem[]
---@field last_line integer
---@field mode Mode|nil
---@field origin_buf integer
---@field prompt_text string

---@class Mode
---@field list_output fun(pattern: string, ctx: AppContext): ListItem[], table[]
---@field initial_mode "insert"|"normal"

---@class TreeNode
---@field _is_file boolean
---@field _path string
---@field [string] TreeNode

---@class TreeEntry
---@field name string
---@field data TreeNode

---@class ListItem
---@field line string
---@field path string
---@field lnum integer|nil
---@field col integer|nil
---@field text string|nil
---@field bufnr integer|nil

local WINHIGHLIGHT = {
	default = "Normal:FuzzyMagikNormal,NormalFloat:FuzzyMagikNormal,FloatBorder:FuzzyMagikBorder",
	active = "Normal:FuzzyMagikNormal,NormalFloat:FuzzyMagikNormal,FloatBorder:FuzzyMagikBorderActive",
}

---@param pattern string
---@return ListItem[]
---@return table[]
local function create_list_output(pattern)
	local chars = {}
	for char in pattern:gmatch(".") do
		table.insert(chars, char)
	end
	local fuzzy_pattern = table.concat(chars, ".*")
	local escaped_pattern = vim.fn.shellescape(fuzzy_pattern)
	local cmd = string.format("rg --files | rg -i %s", escaped_pattern)
	local result = vim.system({ "sh", "-c", cmd }, { text = true }):wait()
	if result.code ~= 0 then
		return { { line = "No files found matching pattern: " .. pattern, path = "" } }, {}
	end

	local files = vim.split(result.stdout or "", "\n", { trimempty = true })
	if #files == 0 then
		return { { line = "No files found matching pattern: " .. pattern, path = "" } }, {}
	end
	table.sort(files)

	local lower_pattern = pattern:lower()
	local items = {}
	local highlights = {}
	for i, filepath in ipairs(files) do
		local name_col = filepath:match("()[^/]*$")
		if name_col > 1 then
			table.insert(highlights, {
				line = i - 1,
				col_start = 0,
				col_end = name_col - 1,
				hl_group = "FuzzyMagikPath",
			})
		end

		local ext_col = filepath:match("[^/]()%.[^./]+$")
		if ext_col then
			table.insert(highlights, {
				line = i - 1,
				col_start = ext_col - 1,
				col_end = #filepath,
				hl_group = "FuzzyMagikExtension",
			})
		end

		local lower_path = filepath:lower()
		local search_from = 1
		for char in lower_pattern:gmatch(".") do
			local col = lower_path:find(char, search_from, true)
			if not col then
				break
			end
			table.insert(highlights, {
				line = i - 1,
				col_start = col - 1,
				col_end = col,
				hl_group = "FuzzyMagikMatch",
			})
			search_from = col + 1
		end

		table.insert(items, {
			line = filepath,
			path = filepath,
		})
	end

	return items, highlights
end

---@param highlights table[]
---@param line integer
---@param offset integer
---@param filepath string
local function add_path_highlights(highlights, line, offset, filepath)
	local name_col = filepath:match("()[^/]*$")
	if name_col > 1 then
		table.insert(highlights, {
			line = line,
			col_start = offset,
			col_end = offset + name_col - 1,
			hl_group = "FuzzyMagikPath",
		})
	end

	local ext_col = filepath:match("[^/]()%.[^./]+$")
	if ext_col then
		table.insert(highlights, {
			line = line,
			col_start = offset + ext_col - 1,
			col_end = offset + #filepath,
			hl_group = "FuzzyMagikExtension",
		})
	end
end

---@param pattern string
---@return ListItem[]
---@return table[]
local function create_grep_output(pattern)
	if pattern == "" then
		return { { line = "", path = "" } }, {}
	end

	local cmd = {
		"rg",
		"--with-filename",
		"--line-number",
		"--column",
		"--no-heading",
		"--color=never",
		"--smart-case",
		"--sort=path",
		"--",
		pattern,
	}
	local result = vim.system(cmd, { text = true }):wait()
	if result.code ~= 0 then
		return { { line = "No matches for pattern: " .. pattern, path = "" } }, {}
	end

	local items = {}
	local highlights = {}
	for _, output_line in ipairs(vim.split(result.stdout or "", "\n", { trimempty = true })) do
		local filepath, lnum, col, text = output_line:match("^(.-):(%d+):(%d+):(.*)$")
		if filepath then
			local line = #items
			local location = ":" .. lnum .. ":" .. col .. ":"
			add_path_highlights(highlights, line, 0, filepath)
			table.insert(highlights, {
				line = line,
				col_start = #filepath,
				col_end = #filepath + #location,
				hl_group = "FuzzyMagikLineNr",
			})
			table.insert(items, {
				line = filepath .. location .. text,
				path = filepath,
				lnum = tonumber(lnum),
				col = tonumber(col),
				text = text,
			})
		end
	end

	if #items == 0 then
		return { { line = "No matches for pattern: " .. pattern, path = "" } }, {}
	end
	return items, highlights
end

---@param pattern string
---@return ListItem[]
---@return table[]
local function create_buffers_output(pattern)
	local lower_pattern = pattern:lower()
	local items = {}
	local highlights = {}
	for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
		local name = info.name ~= "" and vim.fn.fnamemodify(info.name, ":.") or "[No Name]"
		local lower_name = name:lower()
		local match_cols = {}
		local search_from = 1
		for char in lower_pattern:gmatch(".") do
			local col = lower_name:find(char, search_from, true)
			if not col then
				match_cols = nil
				break
			end
			table.insert(match_cols, col)
			search_from = col + 1
		end

		if match_cols then
			local line = #items
			add_path_highlights(highlights, line, 0, name)
			for _, col in ipairs(match_cols) do
				table.insert(highlights, {
					line = line,
					col_start = col - 1,
					col_end = col,
					hl_group = "FuzzyMagikMatch",
				})
			end
			table.insert(items, {
				line = name,
				path = info.name ~= "" and name or "",
				bufnr = info.bufnr,
			})
		end
	end

	if #items == 0 then
		return { { line = "No buffers matching pattern: " .. pattern, path = "" } }, {}
	end
	return items, highlights
end

---@param pattern string
---@param ctx AppContext
---@return ListItem[]
---@return table[]
local function create_workspace_symbols_output(pattern, ctx)
	local responses = vim.lsp.buf_request_sync(ctx.origin_buf, "workspace/symbol", { query = pattern }, 1000)
	local items = {}
	local highlights = {}
	for client_id, response in pairs(responses or {}) do
		local client = vim.lsp.get_client_by_id(client_id)
		if client and response.result then
			local ok, symbols =
				pcall(vim.lsp.util.symbols_to_items, response.result, ctx.origin_buf, client.offset_encoding)
			if ok then
				for _, symbol in ipairs(symbols) do
					local line = #items
					local filepath = vim.fn.fnamemodify(symbol.filename, ":.")
					local prefix = symbol.text .. "  "
					local location = ":" .. symbol.lnum
					table.insert(highlights, {
						line = line,
						col_start = 0,
						col_end = symbol.text:find("]", 1, true) or 0,
						hl_group = "FuzzyMagikKind",
					})
					add_path_highlights(highlights, line, #prefix, filepath)
					table.insert(highlights, {
						line = line,
						col_start = #prefix + #filepath,
						col_end = #prefix + #filepath + #location,
						hl_group = "FuzzyMagikLineNr",
					})
					table.insert(items, {
						line = prefix .. filepath .. location,
						path = filepath,
						lnum = symbol.lnum,
						col = symbol.col,
						text = symbol.text,
					})
				end
			end
		end
	end

	if #items == 0 then
		return { { line = "No symbols matching pattern: " .. pattern, path = "" } }, {}
	end
	return items, highlights
end

---@param pattern string
---@return ListItem[]
---@return table[]
local function create_git_status_output(pattern)
	local root = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
	if root.code ~= 0 then
		return { { line = "Not a git repository", path = "" } }, {}
	end
	local root_dir = vim.trim(root.stdout or "")

	local result = vim.system({ "git", "status", "--porcelain=v1", "-z", "--untracked-files=all" }, { text = true })
		:wait()
	if result.code ~= 0 then
		return { { line = "git status failed", path = "" } }, {}
	end

	local entries = vim.split(result.stdout or "", "\0", { plain = true, trimempty = true })
	local lower_pattern = pattern:lower()
	local items = {}
	local highlights = {}
	local i = 1
	while i <= #entries do
		local entry = entries[i]
		local status = entry:sub(1, 2)
		local filepath = vim.fn.fnamemodify(root_dir .. "/" .. entry:sub(4), ":.")
		if status:find("[RC]") then
			i = i + 1
		end
		i = i + 1

		local lower_path = filepath:lower()
		local match_cols = {}
		local search_from = 1
		for char in lower_pattern:gmatch(".") do
			local col = lower_path:find(char, search_from, true)
			if not col then
				match_cols = nil
				break
			end
			table.insert(match_cols, col)
			search_from = col + 1
		end

		if match_cols then
			local line = #items
			local prefix = status .. " "
			if status == "??" then
				table.insert(highlights, {
					line = line,
					col_start = 0,
					col_end = 2,
					hl_group = "FuzzyMagikGitUntracked",
				})
			else
				if status:sub(1, 1) ~= " " then
					table.insert(highlights, {
						line = line,
						col_start = 0,
						col_end = 1,
						hl_group = "FuzzyMagikGitStaged",
					})
				end
				if status:sub(2, 2) ~= " " then
					table.insert(highlights, {
						line = line,
						col_start = 1,
						col_end = 2,
						hl_group = "FuzzyMagikGitUnstaged",
					})
				end
			end
			add_path_highlights(highlights, line, #prefix, filepath)
			for _, col in ipairs(match_cols) do
				table.insert(highlights, {
					line = line,
					col_start = #prefix + col - 1,
					col_end = #prefix + col,
					hl_group = "FuzzyMagikMatch",
				})
			end
			table.insert(items, {
				line = prefix .. filepath,
				path = filepath,
			})
		end
	end

	if #items == 0 then
		return { { line = "No changed files matching pattern: " .. pattern, path = "" } }, {}
	end
	return items, highlights
end

---@type table<string, Mode>
local MODES = {
	files = { list_output = create_list_output, initial_mode = "insert" },
	grep = { list_output = create_grep_output, initial_mode = "insert" },
	buffers = { list_output = create_buffers_output, initial_mode = "normal" },
	workspace_symbols = { list_output = create_workspace_symbols_output, initial_mode = "insert" },
	git_status = { list_output = create_git_status_output, initial_mode = "normal" },
}

---@param ctx AppContext
---@param pattern string
local function update_results(ctx, pattern)
	vim.bo[ctx.results_buf].modifiable = true

	local highlights = {}
	ctx.current_results, highlights = ctx.mode.list_output(pattern, ctx)
	local lines = {}
	for _, item in ipairs(ctx.current_results) do
		table.insert(lines, item.line)
	end

	vim.api.nvim_buf_set_lines(ctx.results_buf, 0, -1, false, lines)

	local ns_id = vim.api.nvim_create_namespace("tree_highlights")
	for _, hl in ipairs(highlights) do
		vim.api.nvim_buf_set_extmark(ctx.results_buf, ns_id, hl.line, hl.col_start, {
			end_col = hl.col_end,
			hl_group = hl.hl_group,
		})
	end

	vim.bo[ctx.results_buf].modifiable = false
end

---@param ctx AppContext
local function close_ui(ctx)
	if vim.api.nvim_win_is_valid(ctx.prompt_win) then
		vim.api.nvim_win_close(ctx.prompt_win, true)
	end
	if vim.api.nvim_win_is_valid(ctx.results_win) then
		vim.api.nvim_win_close(ctx.results_win, true)
	end
	if vim.api.nvim_win_is_valid(ctx.preview_win) then
		vim.api.nvim_win_close(ctx.preview_win, true)
	end
end

---@param ctx AppContext
local function send_to_quickfix(ctx)
	local entries = {}
	for _, item in ipairs(ctx.current_results) do
		if item.bufnr then
			table.insert(entries, { bufnr = item.bufnr, lnum = 1 })
		elseif item.path ~= "" then
			table.insert(entries, { filename = item.path, lnum = item.lnum or 1, col = item.col, text = item.text })
		end
	end
	close_ui(ctx)
	vim.cmd.stopinsert()
	vim.fn.setqflist(entries, "r")
	vim.cmd.copen()
end

---@param ctx AppContext
---@param item ListItem
---@param lines string[]
---@return boolean
local function set_preview_lines(ctx, item, lines)
	if ctx.current_results[ctx.last_line] ~= item or not vim.api.nvim_win_is_valid(ctx.preview_win) then
		return false
	end

	vim.treesitter.stop(ctx.preview_buf)
	vim.bo[ctx.preview_buf].modifiable = true
	vim.api.nvim_buf_set_lines(ctx.preview_buf, 0, -1, false, lines)
	vim.bo[ctx.preview_buf].modifiable = false
	return true
end

---@param ctx AppContext
---@param item ListItem
---@param lines string[]
---@param ft string|nil
local function show_preview(ctx, item, lines, ft)
	-- Limit lines for performance
	local limit = math.max(500, (item.lnum or 0) + 100)
	if #lines > limit then
		lines = vim.list_slice(lines, 1, limit)
		table.insert(lines, "")
		table.insert(lines, "... (truncated)")
	end

	if not set_preview_lines(ctx, item, lines) then
		return
	end

	local lang = ft and ft ~= "" and vim.treesitter.language.get_lang(ft)
	if lang then
		pcall(vim.treesitter.start, ctx.preview_buf, lang)
	end

	vim.wo[ctx.preview_win].cursorline = item.lnum ~= nil
	vim.api.nvim_win_set_cursor(ctx.preview_win, { math.max(1, math.min(item.lnum or 1, #lines)), 0 })
	if item.lnum then
		vim.api.nvim_win_call(ctx.preview_win, function()
			vim.cmd("normal! zz")
		end)
	end

	-- Update window title with filename
	vim.api.nvim_win_set_config(ctx.preview_win, {
		title = " " .. vim.fn.fnamemodify(item.path, ":t") .. " ",
		title_pos = "center",
	})
end

---@param ctx AppContext
---@param item ListItem
local function update_preview(ctx, item)
	local filepath = item.path

	if item.bufnr then
		show_preview(ctx, item, vim.api.nvim_buf_get_lines(item.bufnr, 0, -1, false), vim.bo[item.bufnr].filetype)
		return
	end

	if vim.fn.filereadable(filepath) == 0 then
		set_preview_lines(ctx, item, { "File not found: " .. filepath })
		return
	end

	local function show_read_error()
		vim.schedule(function()
			set_preview_lines(ctx, item, { "Error reading file" })
		end)
	end

	vim.uv.fs_open(filepath, "r", 438, function(open_err, fd)
		if open_err or not fd then
			show_read_error()
			return
		end
		vim.uv.fs_fstat(fd, function(stat_err, stat)
			if stat_err or not stat then
				vim.uv.fs_close(fd)
				show_read_error()
				return
			end
			vim.uv.fs_read(fd, stat.size, 0, function(read_err, data)
				vim.uv.fs_close(fd)
				if read_err or not data then
					show_read_error()
					return
				end
				vim.schedule(function()
					local lines = vim.split(data, "\n")
					if lines[#lines] == "" then
						table.remove(lines)
					end
					show_preview(ctx, item, lines, vim.filetype.match({ filename = filepath }))
				end)
			end)
		end)
	end)
end

---@param ctx AppContext
---@param mode Mode
---@param resume boolean
local function show_tree_ui(ctx, mode, resume)
	local resume_line = ctx.last_line
	ctx.mode = mode
	ctx.origin_buf = vim.api.nvim_get_current_buf()
	ctx.last_line = -1

	local width = math.floor(vim.o.columns * 0.9)
	local start_col = math.floor((vim.o.columns - width) / 2)

	local height = vim.o.lines - 9
	local results_width = math.floor(width * 0.4)
	local preview_width = width - results_width - 1
	local start_row = 4

	ctx.prompt_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[ctx.prompt_buf].buftype = "prompt"
	vim.bo[ctx.prompt_buf].bufhidden = "wipe"
	vim.fn.prompt_setprompt(ctx.prompt_buf, "> ")
	ctx.prompt_win = vim.api.nvim_open_win(ctx.prompt_buf, true, {
		relative = "editor",
		width = width,
		height = 1,
		row = 1,
		col = start_col,
		style = "minimal",
		border = "rounded",
	})
	vim.wo[ctx.prompt_win].winhighlight = WINHIGHLIGHT.active

	ctx.results_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[ctx.results_buf].buftype = "nofile"
	vim.bo[ctx.results_buf].bufhidden = "wipe"
	vim.bo[ctx.results_buf].modifiable = false
	ctx.results_win = vim.api.nvim_open_win(ctx.results_buf, false, {
		relative = "editor",
		width = results_width - 1,
		height = height,
		row = start_row,
		col = start_col,
		style = "minimal",
		border = "rounded",
	})
	vim.wo[ctx.results_win].cursorline = true
	vim.wo[ctx.results_win].winhighlight = WINHIGHLIGHT.default

	ctx.preview_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[ctx.preview_buf].buftype = "nofile"
	vim.bo[ctx.preview_buf].modifiable = false
	ctx.preview_win = vim.api.nvim_open_win(ctx.preview_buf, false, {
		relative = "editor",
		width = preview_width,
		height = height,
		col = start_col + results_width + 1,
		row = start_row,
		border = "rounded",
		title = " Preview ",
		title_pos = "center",
	})
	vim.wo[ctx.preview_win].number = false
	vim.wo[ctx.preview_win].winhighlight = WINHIGHLIGHT.default

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = ctx.prompt_buf,
		callback = function()
			local text = vim.api.nvim_buf_get_lines(ctx.prompt_buf, 0, 1, false)[1]
			text = text:gsub("^> ", "")
			ctx.prompt_text = text
			update_results(ctx, text)
		end,
	})

	vim.keymap.set("n", "<Esc>", function()
		vim.api.nvim_set_current_win(ctx.results_win)
	end, { buffer = ctx.prompt_buf })
	vim.keymap.set("i", "<Esc>", function()
		vim.api.nvim_set_current_win(ctx.results_win)
	end, { buffer = ctx.prompt_buf })

	vim.keymap.set("n", "<Esc>", function()
		close_ui(ctx)
	end, { buffer = ctx.results_buf })

	vim.keymap.set({ "n", "i" }, "<C-q>", function()
		send_to_quickfix(ctx)
	end, { buffer = ctx.prompt_buf })
	vim.keymap.set("n", "<C-q>", function()
		send_to_quickfix(ctx)
	end, { buffer = ctx.results_buf })

	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = ctx.results_buf,
		callback = function()
			local line_num = vim.api.nvim_win_get_cursor(0)[1]
			if line_num ~= ctx.last_line then
				ctx.last_line = line_num
				local item = ctx.current_results[line_num]
				update_preview(ctx, item)
			end
		end,
	})

	vim.keymap.set("n", "<CR>", function()
		local line_num = vim.api.nvim_win_get_cursor(0)[1]
		local item = ctx.current_results[line_num]
		close_ui(ctx)
		if item.bufnr then
			vim.cmd.buffer(item.bufnr)
		else
			vim.cmd.edit(item.path)
		end
		if item.lnum then
			pcall(vim.api.nvim_win_set_cursor, 0, { item.lnum, (item.col or 1) - 1 })
		end
	end, { buffer = ctx.results_buf })

	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(ctx.prompt_win),
		callback = function()
			close_ui(ctx)
		end,
		once = true,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(ctx.results_win),
		callback = function()
			close_ui(ctx)
		end,
		once = true,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(ctx.preview_buf),
		callback = function()
			close_ui(ctx)
		end,
		once = true,
	})

	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = ctx.prompt_buf,
		callback = function()
			vim.schedule(function()
				if
					vim.api.nvim_get_current_win() ~= ctx.prompt_win
					and vim.api.nvim_get_current_win() ~= ctx.results_win
					and vim.api.nvim_get_current_win() ~= ctx.preview_win
				then
					close_ui(ctx)
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = ctx.results_buf,
		callback = function()
			vim.schedule(function()
				if
					vim.api.nvim_get_current_win() ~= ctx.prompt_win
					and vim.api.nvim_get_current_win() ~= ctx.results_win
					and vim.api.nvim_get_current_win() ~= ctx.preview_win
				then
					close_ui(ctx)
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = ctx.preview_buf,
		callback = function()
			vim.schedule(function()
				if
					vim.api.nvim_get_current_win() ~= ctx.prompt_win
					and vim.api.nvim_get_current_win() ~= ctx.results_win
					and vim.api.nvim_get_current_win() ~= ctx.preview_win
				then
					close_ui(ctx)
				end
			end)
		end,
	})

	vim.api.nvim_create_autocmd("WinEnter", {
		buffer = ctx.prompt_buf,
		callback = function()
			vim.wo[ctx.prompt_win].winhighlight = WINHIGHLIGHT.active
		end,
	})
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = ctx.prompt_buf,
		callback = function()
			vim.wo[ctx.prompt_win].winhighlight = WINHIGHLIGHT.default
		end,
	})
	vim.api.nvim_create_autocmd("WinEnter", {
		buffer = ctx.results_buf,
		callback = function()
			vim.wo[ctx.results_win].winhighlight = WINHIGHLIGHT.active
		end,
	})
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = ctx.results_buf,
		callback = function()
			vim.wo[ctx.results_win].winhighlight = WINHIGHLIGHT.default
		end,
	})
	vim.api.nvim_create_autocmd("WinEnter", {
		buffer = ctx.preview_buf,
		callback = function()
			vim.wo[ctx.preview_win].winhighlight = WINHIGHLIGHT.active
		end,
	})
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = ctx.preview_buf,
		callback = function()
			vim.wo[ctx.preview_win].winhighlight = WINHIGHLIGHT.default
		end,
	})

	if not resume and mode.initial_mode == "insert" then
		vim.cmd.startinsert()
		return
	end

	local line = 1
	if resume then
		vim.api.nvim_buf_set_lines(ctx.prompt_buf, 0, -1, false, { "> " .. ctx.prompt_text })
		update_results(ctx, ctx.prompt_text)
		line = math.max(1, math.min(resume_line, #ctx.current_results))
	else
		ctx.prompt_text = ""
		update_results(ctx, "")
	end
	vim.api.nvim_set_current_win(ctx.results_win)
	vim.api.nvim_win_set_cursor(ctx.results_win, { line, 0 })
	ctx.last_line = line
	update_preview(ctx, ctx.current_results[line])
end

---@type AppContext
local ctx

function M.setup(opts)
	opts = opts or {}

	vim.api.nvim_set_hl(0, "TreePrefix", { fg = "#6c6c6c", bold = true }) -- Blue for directories
	vim.api.nvim_set_hl(0, "TreeDirectory", { fg = "#0d73e8", bold = true }) -- Blue for directories
	vim.api.nvim_set_hl(0, "TreeFile", { link = "Normal" }) -- Normal color for files
	vim.api.nvim_set_hl(0, "FuzzyMagikNormal", { link = "Normal" })
	vim.api.nvim_set_hl(0, "FuzzyMagikBorder", { fg = "#6c6c6c" })
	vim.api.nvim_set_hl(0, "FuzzyMagikBorderActive", { fg = "#00ffd7" })
	vim.api.nvim_set_hl(0, "FuzzyMagikMatch", { fg = "#0d73e8", bold = true })
	vim.api.nvim_set_hl(0, "FuzzyMagikExtension", { fg = "#5fd700" })
	vim.api.nvim_set_hl(0, "FuzzyMagikPath", { fg = "#af87d7" })
	vim.api.nvim_set_hl(0, "FuzzyMagikLineNr", { fg = "#6c6c6c" })
	vim.api.nvim_set_hl(0, "FuzzyMagikKind", { fg = "#d7af5f" })
	vim.api.nvim_set_hl(0, "FuzzyMagikGitStaged", { fg = "#5fd700" })
	vim.api.nvim_set_hl(0, "FuzzyMagikGitUnstaged", { fg = "#d75f5f" })
	vim.api.nvim_set_hl(0, "FuzzyMagikGitUntracked", { fg = "#6c6c6c" })

	ctx = {
		prompt_win = 0,
		prompt_buf = 0,
		results_win = 0,
		results_buf = 0,
		preview_win = 0,
		preview_buf = 0,
		current_results = {},
		last_line = -1,
		mode = nil,
		origin_buf = 0,
		prompt_text = "",
	}
end

function M.find_files()
	show_tree_ui(ctx, MODES.files, false)
end

function M.live_grep()
	show_tree_ui(ctx, MODES.grep, false)
end

function M.buffers()
	show_tree_ui(ctx, MODES.buffers, false)
end

function M.lsp_dynamic_workspace_symbols()
	show_tree_ui(ctx, MODES.workspace_symbols, false)
end

function M.git_status()
	show_tree_ui(ctx, MODES.git_status, false)
end

function M.resume()
	if not ctx.mode then
		return
	end
	show_tree_ui(ctx, ctx.mode, true)
end

return M
