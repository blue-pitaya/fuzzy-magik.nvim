local M = {}

---@class AppContext
---@field prompt_win integer
---@field prompt_buf integer
---@field results_win integer
---@field results_buf integer
---@field preview_win integer
---@field preview_buf integer
---@field current_results ListItem[]
---@field has_devicons boolean
---@field devicons unknown
---@field last_line integer

---@param ctx AppContext
---@param name string
---@param is_directory boolean
---@return string icon
---@return string|nil hl_group
local function get_icon(ctx, name, is_directory)
	if is_directory then
		return "", "TreeDirectory"
	end

	if ctx.has_devicons then
		local icon, hl = ctx.devicons.get_icon(name, nil, { default = true })
		return icon .. " ", hl
	end

	return " ", nil
end

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

local TREE_CHARS = {
	vertical = "│ ",
	branch = "├─",
	last = "└─",
	space = "  ",
}

local WINHIGHLIGHT = {
	default = "Normal:FuzzyMagikNormal,NormalFloat:FuzzyMagikNormal,FloatBorder:FuzzyMagikBorder",
	active = "Normal:FuzzyMagikNormal,NormalFloat:FuzzyMagikNormal,FloatBorder:FuzzyMagikBorderActive",
}

---@param files string[]
---@return TreeNode
local function build_tree(files)
	---@type TreeNode
	local tree = {
		_is_file = false,
		_path = "",
	}

	for _, filepath in ipairs(files) do
		if filepath ~= "" then
			local parts = vim.split(filepath, "/", { plain = true })
			local current = tree

			for i, part in ipairs(parts) do
				if not current[part] then
					current[part] = {
						_is_file = (i == #parts),
						_path = table.concat(vim.list_slice(parts, 1, i), "/"),
					}
				end
				---@diagnostic disable-next-line: cast-local-type
				current = current[part]
			end
		end
	end

	return tree
end

---@param entries TreeNode
---@return TreeEntry[]
local function sort_entries(entries)
	local sorted = {}

	for name, data in pairs(entries) do
		if name ~= "_is_file" and name ~= "_path" then
			table.insert(sorted, { name = name, data = data })
		end
	end

	table.sort(sorted, function(a, b)
		local a_is_file = a.data._is_file
		local b_is_file = b.data._is_file

		if a_is_file ~= b_is_file then
			return not a_is_file
		end
		return a.name < b.name
	end)

	return sorted
end

---@param ctx AppContext
---@param node TreeNode
---@param prefix string
---@param items ListItem[]
---@param highlights table[]
local function generate_tree_lines(ctx, node, prefix, items, highlights)
	local entries = sort_entries(node)
	for i, entry in ipairs(entries) do
		local name = entry.name
		local data = entry.data
		local is_last_entry = (i == #entries)
		local icon, icon_hl = get_icon(ctx, name, not data._is_file)
		local connector = is_last_entry and TREE_CHARS.last or TREE_CHARS.branch

		-- Build line with icon inserted
		local line = prefix .. connector .. icon .. name

		local line_num = #items
		local prefix_len = #prefix
		local connector_len = #connector
		local icon_start = prefix_len + connector_len
		local icon_len = vim.fn.strwidth(icon)
		local name_start = icon_start + icon_len

		-- Highlight prefix (tree structure before connector)
		if prefix_len > 0 then
			table.insert(highlights, {
				line = line_num,
				col_start = 0,
				col_end = prefix_len,
				hl_group = "TreePrefix",
			})
		end

		-- Highlight connector
		table.insert(highlights, {
			line = line_num,
			col_start = prefix_len,
			col_end = icon_start,
			hl_group = "TreePrefix",
		})

		-- Highlight icon
		if icon_hl then
			table.insert(highlights, {
				line = line_num,
				col_start = icon_start,
				col_end = name_start,
				hl_group = icon_hl,
			})
		end

		-- Highlight name (file or directory)
		if data._is_file then
			table.insert(highlights, {
				line = line_num,
				col_start = name_start,
				col_end = name_start + #name,
				hl_group = "TreeFile",
			})
		else
			line = line .. "/"
			table.insert(highlights, {
				line = line_num,
				col_start = name_start,
				col_end = name_start + #name + 1, -- +1 for the "/"
				hl_group = "TreeDirectory",
			})
		end

		table.insert(items, {
			line = line,
			path = data._path,
		})

		if not data._is_file then
			local new_prefix = prefix .. (is_last_entry and TREE_CHARS.space or TREE_CHARS.vertical)
			generate_tree_lines(ctx, data, new_prefix, items, highlights)
		end
	end
end

---@param ctx AppContext
---@param pattern string
---@return ListItem[]
---@return table[]
local function create_tree_output(ctx, pattern)
	local chars = {}
	for char in pattern:gmatch(".") do
		table.insert(chars, char)
	end
	local fuzzy_pattern = table.concat(chars, ".*")
	local escaped_pattern = vim.fn.shellescape(fuzzy_pattern)
	local cmd = string.format("rg --files | rg -i %s", escaped_pattern)
	local result = vim.system({ "sh", "-c", cmd }, { text = true }):wait()
	if result.code ~= 0 then
		return { "No files found matching pattern: " .. pattern }, {}
	end

	local files = vim.split(result.stdout or "", "\n", { trimempty = true })
	if #files == 0 then
		return { "No files found matching pattern: " .. pattern }, {}
	end

	local tree = build_tree(files)

	local cwd = vim.fn.getcwd()
	local items = {
		{
			line = cwd,
			path = cwd,
		},
	}
	local highlights = {
		{
			line = 0,
			col_start = 0,
			col_end = #cwd,
			hl_group = "TreeDirectory",
		},
	}
	generate_tree_lines(ctx, tree, "", items, highlights)

	return items, highlights
end

---@param ctx AppContext
---@param pattern string
---@return ListItem[]
---@return table[]
local function create_list_output(ctx, pattern)
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

	local lower_pattern = pattern:lower()
	local items = {}
	local highlights = {}
	for i, filepath in ipairs(files) do
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

---@param ctx AppContext
---@param pattern string
local function update_results(ctx, pattern)
	vim.bo[ctx.results_buf].modifiable = true

	local highlights = {}
	ctx.current_results, highlights = create_list_output(ctx, pattern)
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
---@param item ListItem
local function update_preview(ctx, item)
	vim.bo[ctx.preview_buf].modifiable = true

	local filepath = item.path

	if vim.fn.filereadable(filepath) == 0 then
		vim.api.nvim_buf_set_lines(ctx.preview_buf, 0, -1, false, { "File not found: " .. filepath })
		vim.bo[ctx.preview_buf].modifiable = false
		return
	end

	-- Read file with error handling
	local ok, lines = pcall(vim.fn.readfile, filepath)
	if not ok then
		vim.api.nvim_buf_set_lines(ctx.preview_buf, 0, -1, false, { "Error reading file" })
		vim.bo[ctx.preview_buf].modifiable = false
		return
	end

	-- Limit lines for performance
	if #lines > 500 then
		lines = vim.list_slice(lines, 1, 500)
		table.insert(lines, "")
		table.insert(lines, "... (truncated)")
	end

	vim.api.nvim_buf_set_lines(ctx.preview_buf, 0, -1, false, lines)

	-- Set filetype for syntax highlighting
	local ft = vim.filetype.match({ filename = filepath })
	if ft then
		vim.bo[ctx.preview_buf].filetype = ft
	end

	-- Update window title with filename
	vim.api.nvim_win_set_config(ctx.preview_win, {
		title = " " .. vim.fn.fnamemodify(filepath, ":t") .. " ",
		title_pos = "center",
	})

	vim.bo[ctx.preview_buf].modifiable = false
end

---@param ctx AppContext
local function show_tree_ui(ctx)
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
		vim.cmd.edit(item.path)
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

	vim.cmd.startinsert()
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

	local has_devicons, devicons = pcall(require, "nvim-web-devicons")

	ctx = {
		prompt_win = 0,
		prompt_buf = 0,
		results_win = 0,
		results_buf = 0,
		preview_win = 0,
		preview_buf = 0,
		current_results = {},
		has_devicons = has_devicons,
		devicons = devicons,
		last_line = -1,
	}
end

function M.find_files()
	show_tree_ui(ctx)
end

return M
