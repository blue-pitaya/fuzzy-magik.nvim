local utils = require("fuzzy-magik.utils")
local app_state = require("fuzzy-magik.app_state")
local WindowsService = require("fuzzy-magik.windows.windows_service")
local find_files = require("fuzzy-magik.pickers.find_files").new()

local M = {}

local WINHIGHLIGHT = utils.WINHIGHLIGHT

local HIGHLIGHTS = {
	FuzzyMagikNormal = { link = "Normal" },
	FuzzyMagikBorder = { fg = "#767676" },
	FuzzyMagikBorderActive = { fg = "#00ffff" },
	FuzzyMagikMatch = { fg = "#00afd7", bold = true },
	FuzzyMagikExtension = { fg = "#b8bb26" },
	FuzzyMagikPath = { fg = "#bb9af7" },
	FuzzyMagikLineNr = { fg = "#767676" },
	FuzzyMagikKind = { fg = "#f2a475" },
	FuzzyMagikGitStaged = { fg = "#b8bb26" },
	FuzzyMagikGitUnstaged = { fg = "#e77969" },
	FuzzyMagikGitUntracked = { fg = "#767676" },
	FuzzyMagikMarked = { fg = "#ff64b5" },
}

local PROMPT = utils.PROMPT
local PREVIEW_MIN_LINES = 500
local PREVIEW_LINES_AFTER_MATCH = 100
local LSP_TIMEOUT_MS = 1000
local NAMESPACE = vim.api.nvim_create_namespace("tree_highlights")

---@class FuzzyMagikItem
---@field line string
---@field path string
---@field lnum? integer
---@field col? integer
---@field text? string
---@field bufnr? integer
---@field is_dir? boolean

local prompt = app_state.prompt
local results = app_state.results
local preview = app_state.preview
local state = app_state.state
local windows_service = WindowsService.new(prompt, results, preview)

---@param pattern string
local function create_grep_output(pattern)
	if pattern == "" then
		return utils.message("")
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
		return utils.message("No matches for pattern: " .. pattern)
	end

	---@type FuzzyMagikItem[]
	local items = {}
	for _, output_line in ipairs(vim.split(result.stdout or "", "\n", { trimempty = true })) do
		local filepath, lnum, col, text = output_line:match("^(.-):(%d+):(%d+):(.*)$")
		if filepath then
			local line = #items
			local location = ":" .. lnum .. ":" .. col .. ":"
			utils.add_path_highlights(line, 0, filepath)
			table.insert(utils.highlights, {
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
		return utils.message("No matches for pattern: " .. pattern)
	end
	return items
end

---@param pattern string
local function create_buffers_output(pattern)
	---@type FuzzyMagikItem[]
	local items = {}
	for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
		local name = info.name ~= "" and vim.fn.fnamemodify(info.name, ":.") or "[No Name]"
		local cols = utils.fuzzy_match_cols(name, pattern)
		if cols then
			local line = #items
			utils.add_path_highlights(line, 0, name)
			utils.add_match_highlights(line, 0, cols)
			table.insert(items, {
				line = name,
				path = info.name ~= "" and name or "",
				bufnr = info.bufnr,
			})
		end
	end

	if #items == 0 then
		return utils.message("No buffers matching pattern: " .. pattern)
	end
	return items
end

---@param pattern string
---@param origin_buf integer
local function create_workspace_symbols_output(pattern, origin_buf)
	local responses = vim.lsp.buf_request_sync(origin_buf, "workspace/symbol", { query = pattern }, LSP_TIMEOUT_MS)
	---@type FuzzyMagikItem[]
	local items = {}
	for client_id, response in pairs(responses or {}) do
		local client = vim.lsp.get_client_by_id(client_id)
		if client and response.result then
			local ok, symbols =
				pcall(vim.lsp.util.symbols_to_items, response.result, origin_buf, client.offset_encoding)
			if ok then
				for _, symbol in ipairs(symbols) do
					local line = #items
					local filepath = vim.fn.fnamemodify(symbol.filename, ":.")
					local prefix = symbol.text .. "  "
					local location = ":" .. symbol.lnum
					table.insert(utils.highlights, {
						line = line,
						col_start = 0,
						col_end = symbol.text:find("]", 1, true) or 0,
						hl_group = "FuzzyMagikKind",
					})
					utils.add_path_highlights(line, #prefix, filepath)
					table.insert(utils.highlights, {
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
		return utils.message("No symbols matching pattern: " .. pattern)
	end
	return items
end

---@param pattern string
local function create_git_status_output(pattern)
	local root = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
	if root.code ~= 0 then
		return utils.message("Not a git repository")
	end
	local root_dir = vim.trim(root.stdout or "")

	local result = vim.system({ "git", "status", "--porcelain=v1", "-z", "--untracked-files=all" }, { text = true })
		:wait()
	if result.code ~= 0 then
		return utils.message("git status failed")
	end

	local entries = vim.split(result.stdout or "", "\0", { plain = true, trimempty = true })
	---@type FuzzyMagikItem[]
	local items = {}
	local i = 1
	while i <= #entries do
		local entry = entries[i]
		local status = entry:sub(1, 2)
		local filepath = vim.fn.fnamemodify(root_dir .. "/" .. entry:sub(4), ":.")
		if status:find("[RC]") then
			i = i + 1
		end
		i = i + 1

		local cols = utils.fuzzy_match_cols(filepath, pattern)
		if cols then
			local line = #items
			local prefix = status .. " "
			if status == "??" then
				table.insert(utils.highlights, {
					line = line,
					col_start = 0,
					col_end = 2,
					hl_group = "FuzzyMagikGitUntracked",
				})
			else
				if status:sub(1, 1) ~= " " then
					table.insert(utils.highlights, {
						line = line,
						col_start = 0,
						col_end = 1,
						hl_group = "FuzzyMagikGitStaged",
					})
				end
				if status:sub(2, 2) ~= " " then
					table.insert(utils.highlights, {
						line = line,
						col_start = 1,
						col_end = 2,
						hl_group = "FuzzyMagikGitUnstaged",
					})
				end
			end
			utils.add_path_highlights(line, #prefix, filepath)
			utils.add_match_highlights(line, #prefix, cols)
			table.insert(items, {
				line = prefix .. filepath,
				path = filepath,
			})
		end
	end

	if #items == 0 then
		return utils.message("No changed files matching pattern: " .. pattern)
	end
	return items
end

---@param pattern string
local function create_diagnostics_output(pattern)
	local diagnostics = vim.diagnostic.get()
	table.sort(diagnostics, function(a, b)
		if a.severity ~= b.severity then
			return a.severity < b.severity
		end
		if a.bufnr ~= b.bufnr then
			return a.bufnr < b.bufnr
		end
		return a.lnum < b.lnum
	end)

	---@type FuzzyMagikItem[]
	local items = {}
	for _, diagnostic in ipairs(diagnostics) do
		local severity = vim.diagnostic.severity[diagnostic.severity]
		local filepath = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(diagnostic.bufnr), ":.")
		local location = ":" .. diagnostic.lnum + 1 .. ":" .. diagnostic.col + 1 .. ": "
		local text = diagnostic.message:gsub("\n", " ")
		local body = filepath .. location .. text
		local cols = utils.fuzzy_match_cols(body, pattern)
		if cols then
			local line = #items
			local prefix = severity:sub(1, 1) .. " "
			table.insert(utils.highlights, {
				line = line,
				col_start = 0,
				col_end = 1,
				hl_group = "Diagnostic" .. severity:sub(1, 1) .. severity:sub(2):lower(),
			})
			utils.add_path_highlights(line, #prefix, filepath)
			table.insert(utils.highlights, {
				line = line,
				col_start = #prefix + #filepath,
				col_end = #prefix + #filepath + #location,
				hl_group = "FuzzyMagikLineNr",
			})
			utils.add_match_highlights(line, #prefix, cols)
			table.insert(items, {
				line = prefix .. body,
				path = filepath,
				lnum = diagnostic.lnum + 1,
				col = diagnostic.col + 1,
				text = text,
			})
		end
	end

	if #items == 0 then
		return utils.message("No diagnostics matching pattern: " .. pattern)
	end
	return items
end

---@param method string
local function request_lsp_locations(method)
	local buf = vim.api.nvim_get_current_buf()
	local clients = vim.lsp.get_clients({ bufnr = buf, method = method })
	if #clients == 0 then
		return {}
	end

	local params = vim.lsp.util.make_position_params(0, clients[1].offset_encoding)
	if method == "textDocument/references" then
		params.context = { includeDeclaration = true }
	end
	local responses = vim.lsp.buf_request_sync(buf, method, params, LSP_TIMEOUT_MS)
	local locations = {}
	for client_id, response in pairs(responses or {}) do
		local client = vim.lsp.get_client_by_id(client_id)
		if client and response.result then
			local result = vim.islist(response.result) and response.result or { response.result }
			vim.list_extend(locations, vim.lsp.util.locations_to_items(result, client.offset_encoding))
		end
	end
	return locations
end

---@param pattern string
local function create_lsp_locations_output(pattern)
	---@type FuzzyMagikItem[]
	local items = {}
	for _, entry in ipairs(state.lsp_locations) do
		local filepath = vim.fn.fnamemodify(entry.filename, ":.")
		local location = ":" .. entry.lnum .. ":" .. entry.col
		local cols = utils.fuzzy_match_cols(filepath, pattern)
		if cols then
			local line = #items
			utils.add_path_highlights(line, 0, filepath)
			table.insert(utils.highlights, {
				line = line,
				col_start = #filepath,
				col_end = #filepath + #location,
				hl_group = "FuzzyMagikLineNr",
			})
			utils.add_match_highlights(line, 0, cols)
			table.insert(items, {
				line = filepath .. location,
				path = filepath,
				lnum = entry.lnum,
				col = entry.col,
				text = entry.text,
			})
		end
	end

	if #items == 0 then
		return utils.message("No locations matching pattern: " .. pattern)
	end
	return items
end

---@param dir string
---@param depth integer
---@param entries table[]
local function collect_tree_entries(dir, depth, entries)
	local children = {}
	for name in vim.fs.dir(dir) do
		local path = vim.fs.joinpath(dir, name)
		table.insert(children, { name = name, path = path, is_dir = vim.fn.isdirectory(path) == 1, depth = depth })
	end
	table.sort(children, function(a, b)
		if a.is_dir ~= b.is_dir then
			return a.is_dir
		end
		return a.name < b.name
	end)

	for _, child in ipairs(children) do
		table.insert(entries, child)
		if child.is_dir and state.expanded[child.path] then
			collect_tree_entries(child.path, depth + 1, entries)
		end
	end
end

---@param pattern string
local function create_file_browser_output(pattern)
	local entries = {}
	collect_tree_entries(state.browser_dir, 0, entries)

	---@type FuzzyMagikItem[]
	local items = {}
	for _, entry in ipairs(entries) do
		local name = entry.is_dir and entry.name .. "/" or entry.name
		local cols = utils.fuzzy_match_cols(name, pattern)
		if cols then
			local line = #items
			local mark = state.marked[entry.path] and "+ " or "  "
			local icon = "  "
			if entry.is_dir then
				icon = state.expanded[entry.path] and "▾ " or "▸ "
			end
			local prefix = mark .. string.rep("  ", entry.depth) .. icon
			table.insert(utils.highlights, {
				line = line,
				col_start = 0,
				col_end = 1,
				hl_group = "FuzzyMagikMarked",
			})
			if entry.is_dir then
				table.insert(utils.highlights, {
					line = line,
					col_start = #prefix - #icon,
					col_end = #prefix + #name,
					hl_group = "FuzzyMagikPath",
				})
			else
				utils.add_path_highlights(line, #prefix, name)
			end
			utils.add_match_highlights(line, #prefix, cols)
			table.insert(items, {
				line = prefix .. name,
				path = entry.path,
				is_dir = entry.is_dir,
			})
		end
	end

	if #items == 0 then
		return utils.message("No entries matching pattern: " .. pattern)
	end
	return items
end

---@param list_output fun(pattern: string, origin_buf: integer): table[]
---@param pattern string
---@param origin_buf integer
local function update_results(list_output, pattern, origin_buf)
	vim.bo[results.buf].modifiable = true

	utils.highlights = {}
	results.items = list_output(pattern, origin_buf)
	local lines = {}
	for _, item in ipairs(results.items) do
		table.insert(lines, item.line)
	end

	vim.api.nvim_buf_set_lines(results.buf, 0, -1, false, lines)

	vim.api.nvim_buf_clear_namespace(results.buf, NAMESPACE, 0, -1)
	for _, hl in ipairs(utils.highlights) do
		vim.api.nvim_buf_set_extmark(results.buf, NAMESPACE, hl.line, hl.col_start, {
			end_col = hl.col_end,
			hl_group = hl.hl_group,
		})
	end

	vim.bo[results.buf].modifiable = false
end

local function is_open()
	return prompt.win ~= 0 and vim.api.nvim_win_is_valid(prompt.win)
end

local function close_ui()
	for _, part in ipairs({ prompt, results, preview }) do
		if vim.api.nvim_win_is_valid(part.win) then
			vim.api.nvim_win_close(part.win, true)
		end
	end
end

local function send_to_quickfix()
	local entries = {}
	for _, item in ipairs(results.items) do
		if item.bufnr then
			table.insert(entries, { bufnr = item.bufnr, lnum = 1 })
		elseif item.path ~= "" then
			table.insert(entries, { filename = item.path, lnum = item.lnum or 1, col = item.col, text = item.text })
		end
	end
	close_ui()
	vim.cmd.stopinsert()
	vim.fn.setqflist(entries, "r")
	vim.cmd.copen()
end

---@param item table
---@param lines string[]
local function set_preview_lines(item, lines)
	if results.items[results.last_line] ~= item or not vim.api.nvim_win_is_valid(preview.win) then
		return false
	end

	vim.treesitter.stop(preview.buf)
	vim.bo[preview.buf].modifiable = true
	vim.api.nvim_buf_set_lines(preview.buf, 0, -1, false, lines)
	vim.bo[preview.buf].modifiable = false
	return true
end

---@param item table
---@param lines string[]
---@param ft string|nil
local function show_preview(item, lines, ft)
	-- Limit lines for performance
	local limit = math.max(PREVIEW_MIN_LINES, (item.lnum or 0) + PREVIEW_LINES_AFTER_MATCH)
	if #lines > limit then
		lines = vim.list_slice(lines, 1, limit)
		table.insert(lines, "")
		table.insert(lines, "... (truncated)")
	end

	if not set_preview_lines(item, lines) then
		return
	end

	local lang = ft and ft ~= "" and vim.treesitter.language.get_lang(ft)
	if lang then
		pcall(vim.treesitter.start, preview.buf, lang)
	end

	vim.wo[preview.win].cursorline = item.lnum ~= nil
	vim.api.nvim_win_set_cursor(preview.win, { math.max(1, math.min(item.lnum or 1, #lines)), 0 })
	if item.lnum then
		vim.api.nvim_win_call(preview.win, function()
			vim.cmd("normal! zz")
		end)
	end

	-- Update window title with filename
	vim.api.nvim_win_set_config(preview.win, {
		title = " " .. vim.fn.fnamemodify(item.path, ":t") .. " ",
		title_pos = "center",
	})
end

---@param item table
local function update_preview(item)
	if item.is_dir then
		local lines = {}
		for name, entry_type in vim.fs.dir(item.path) do
			table.insert(lines, entry_type == "directory" and name .. "/" or name)
		end
		table.sort(lines)
		show_preview(item, lines, nil)
		return
	end

	if item.bufnr then
		show_preview(item, vim.api.nvim_buf_get_lines(item.bufnr, 0, -1, false), vim.bo[item.bufnr].filetype)
		return
	end

	if vim.fn.filereadable(item.path) == 0 then
		set_preview_lines(item, { "File not found: " .. item.path })
		return
	end

	local function show_read_error()
		vim.schedule(function()
			set_preview_lines(item, { "Error reading file" })
		end)
	end

	vim.uv.fs_open(item.path, "r", 438, function(open_err, fd)
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
					show_preview(item, lines, vim.filetype.match({ filename = item.path }))
				end)
			end)
		end)
	end)
end

local function current_item()
	return results.items[vim.api.nvim_win_get_cursor(results.win)[1]]
end

local function target_dir()
	local item = current_item()
	if item.path == "" then
		return state.browser_dir
	end
	return vim.fs.dirname(item.path)
end

local function selected_paths()
	local paths = vim.tbl_keys(state.marked)
	if #paths > 0 then
		table.sort(paths)
		return paths
	end

	local item = current_item()
	if item.path == "" then
		return {}
	end
	return { item.path }
end

---@param path string
local function buffers_under(path)
	local bufs = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local name = vim.api.nvim_buf_get_name(buf)
		if name == path or vim.startswith(name, path .. "/") then
			table.insert(bufs, buf)
		end
	end
	return bufs
end

---@param src string
---@param dst string
local function copy_path(src, dst)
	if vim.fn.isdirectory(src) == 0 then
		local ok, err = vim.uv.fs_copyfile(src, dst)
		if not ok then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return
	end

	vim.fn.mkdir(dst, "p")
	for name in vim.fs.dir(src) do
		copy_path(vim.fs.joinpath(src, name), vim.fs.joinpath(dst, name))
	end
end

---@param old string
---@param new string
local function move_path(old, new)
	local ok, err, err_name = vim.uv.fs_rename(old, new)
	if not ok then
		if err_name ~= "EXDEV" then
			vim.notify(err, vim.log.levels.ERROR)
			return
		end
		copy_path(old, new)
		vim.fn.delete(old, "rf")
	end

	for _, buf in ipairs(buffers_under(old)) do
		vim.api.nvim_buf_set_name(buf, new .. vim.api.nvim_buf_get_name(buf):sub(#old + 1))
		if vim.api.nvim_buf_is_loaded(buf) and not vim.bo[buf].modified then
			vim.api.nvim_buf_call(buf, function()
				vim.cmd("silent! write!")
			end)
		end
	end
end

local function set_browser_title()
	vim.api.nvim_win_set_config(results.win, {
		title = " " .. vim.fn.fnamemodify(state.browser_dir, ":~") .. " ",
		title_pos = "center",
	})
end

local function refresh_browser()
	set_browser_title()
	update_results(create_file_browser_output, prompt.text, state.origin_buf)
	local line = vim.api.nvim_win_get_cursor(results.win)[1]
	results.last_line = line
	update_preview(results.items[line])
end

---@param dir string
local function open_browser_dir(dir)
	state.browser_dir = dir
	prompt.text = ""
	vim.api.nvim_buf_set_lines(prompt.buf, 0, -1, false, { PROMPT })
	vim.api.nvim_win_set_cursor(results.win, { 1, 0 })
	refresh_browser()
end

local function toggle_mark()
	local item = current_item()
	if item.path == "" then
		return
	end

	state.marked[item.path] = not state.marked[item.path] or nil
	refresh_browser()
end

---@param action string
local function set_clipboard(action)
	local paths = selected_paths()
	if #paths == 0 then
		return
	end

	state.clipboard = { action = action, paths = paths }
	state.marked = {}
	refresh_browser()
	vim.notify(action:sub(1, 1):upper() .. action:sub(2) .. ": " .. #paths .. " item(s)")
end

local function paste_clipboard()
	local dir = target_dir()
	state.expanded[dir] = true
	for _, path in ipairs(state.clipboard.paths) do
		local target = vim.fs.joinpath(dir, vim.fs.basename(path))
		if vim.uv.fs_stat(target) then
			vim.notify("Already exists: " .. target, vim.log.levels.WARN)
		elseif vim.startswith(dir .. "/", path .. "/") then
			vim.notify("Cannot paste into itself: " .. path, vim.log.levels.WARN)
		elseif state.clipboard.action == "cut" then
			move_path(path, target)
		else
			copy_path(path, target)
		end
	end
	if state.clipboard.action == "cut" then
		state.clipboard = { action = nil, paths = {} }
	end
	refresh_browser()
end

local function delete_selected()
	local paths = selected_paths()
	if #paths == 0 or vim.fn.confirm("Delete " .. #paths .. " item(s)?", "&Yes\n&No", 2) ~= 1 then
		return
	end

	for _, path in ipairs(paths) do
		local res = vim.system({ "gio", "trash", path }, { text = true }):wait()
		if res.code ~= 0 then
			vim.notify(res.stderr, vim.log.levels.ERROR)
		end
		for _, buf in ipairs(buffers_under(path)) do
			if not vim.bo[buf].modified then
				pcall(vim.api.nvim_buf_delete, buf, { force = true })
			end
		end
	end
	state.marked = {}
	refresh_browser()
end

local function rename_current()
	local item = current_item()
	if item.path == "" then
		return
	end

	local name = vim.fn.input("Rename: ", vim.fs.basename(item.path))
	local target = vim.fs.joinpath(vim.fs.dirname(item.path), name)
	if name == "" or target == item.path then
		return
	end

	if vim.uv.fs_stat(target) then
		vim.notify("Already exists: " .. target, vim.log.levels.WARN)
		return
	end

	vim.fn.mkdir(vim.fs.dirname(target), "p")
	move_path(item.path, target)
	refresh_browser()
end

local function create_path()
	local name = vim.fn.input("Create: ")
	if name == "" then
		return
	end

	local dir = target_dir()
	local path = vim.fs.joinpath(dir, name)
	if vim.uv.fs_stat(path) then
		vim.notify("Already exists: " .. path, vim.log.levels.WARN)
		return
	end

	state.expanded[dir] = true
	if vim.endswith(name, "/") then
		vim.fn.mkdir(path, "p")
	else
		vim.fn.mkdir(vim.fs.dirname(path), "p")
		vim.fn.writefile({}, path)
	end
	refresh_browser()
end

---@param list_output fun(pattern: string, origin_buf: integer): table[]
---@param start_insert boolean
---@param resume boolean
local function show(list_output, start_insert, resume)
	if is_open() then
		return
	end
	local resume_line = results.last_line
	state.list_output = list_output
	state.start_insert = start_insert
	state.origin_buf = vim.api.nvim_get_current_buf()
	find_files.files = nil
	results.last_line = -1

	windows_service:open()

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = prompt.buf,
		callback = function()
			local text = vim.api.nvim_buf_get_lines(prompt.buf, 0, 1, false)[1]
			text = text:gsub("^" .. vim.pesc(PROMPT), "")
			prompt.text = text
			update_results(list_output, text, state.origin_buf)
		end,
	})

	vim.keymap.set({ "n", "i" }, "<Esc>", function()
		vim.api.nvim_set_current_win(results.win)
	end, { buffer = prompt.buf })
	vim.keymap.set({ "n", "i" }, "<CR>", function()
		vim.api.nvim_set_current_win(results.win)
	end, { buffer = prompt.buf })
	vim.keymap.set("n", "<Esc>", close_ui, { buffer = results.buf })
	vim.keymap.set("n", "i", function()
		vim.api.nvim_set_current_win(prompt.win)
		vim.cmd.startinsert({ bang = true })
	end, { buffer = results.buf })

	vim.keymap.set({ "n", "i" }, "<C-q>", send_to_quickfix, { buffer = prompt.buf })
	vim.keymap.set("n", "<C-q>", send_to_quickfix, { buffer = results.buf })

	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = results.buf,
		callback = function()
			local line_num = vim.api.nvim_win_get_cursor(0)[1]
			if line_num ~= results.last_line then
				results.last_line = line_num
				update_preview(results.items[line_num])
			end
		end,
	})

	vim.keymap.set("n", "<CR>", function()
		local line_num = vim.api.nvim_win_get_cursor(0)[1]
		local item = results.items[line_num]
		if item.is_dir then
			state.expanded[item.path] = not state.expanded[item.path] or nil
			refresh_browser()
			return
		end
		close_ui()
		if item.bufnr then
			vim.cmd.buffer(item.bufnr)
		else
			vim.cmd.edit(item.path)
		end
		if item.lnum then
			pcall(vim.api.nvim_win_set_cursor, 0, { item.lnum, (item.col or 1) - 1 })
		end
	end, { buffer = results.buf })

	if list_output == create_file_browser_output then
		set_browser_title()
		vim.keymap.set("n", "-", function()
			state.expanded[state.browser_dir] = true
			open_browser_dir(vim.fs.dirname(state.browser_dir))
		end, { buffer = results.buf })
		vim.keymap.set("n", "o", "<CR>", { buffer = results.buf, remap = true })
		vim.keymap.set("n", "<Tab>", toggle_mark, { buffer = results.buf })
		vim.keymap.set("n", "x", function()
			set_clipboard("cut")
		end, { buffer = results.buf })
		vim.keymap.set("n", "y", function()
			set_clipboard("copy")
		end, { buffer = results.buf })
		vim.keymap.set("n", "p", paste_clipboard, { buffer = results.buf })
		vim.keymap.set("n", "d", delete_selected, { buffer = results.buf })
		vim.keymap.set("n", "r", rename_current, { buffer = results.buf })
		vim.keymap.set("n", "a", create_path, { buffer = results.buf })
	end

	for _, part in ipairs({ prompt, results, preview }) do
		vim.api.nvim_create_autocmd("WinClosed", {
			pattern = tostring(part.win),
			callback = close_ui,
			once = true,
		})
		vim.api.nvim_create_autocmd("WinEnter", {
			buffer = part.buf,
			callback = function()
				vim.wo[part.win].winhighlight = WINHIGHLIGHT.active
			end,
		})
		vim.api.nvim_create_autocmd("WinLeave", {
			buffer = part.buf,
			callback = function()
				vim.wo[part.win].winhighlight = WINHIGHLIGHT.default
				vim.schedule(function()
					local win = vim.api.nvim_get_current_win()
					if win ~= prompt.win and win ~= results.win and win ~= preview.win then
						close_ui()
					end
				end)
			end,
		})
	end

	if not resume and start_insert then
		vim.cmd.startinsert()
		return
	end

	local line = 1
	if resume then
		vim.api.nvim_buf_set_lines(prompt.buf, 0, -1, false, { PROMPT .. prompt.text })
		update_results(list_output, prompt.text, state.origin_buf)
		line = math.max(1, math.min(resume_line, #results.items))
	else
		prompt.text = ""
		update_results(list_output, "", state.origin_buf)
	end
	vim.api.nvim_set_current_win(results.win)
	vim.api.nvim_win_set_cursor(results.win, { line, 0 })
	results.last_line = line
	update_preview(results.items[line])
end

---@param method string
local function show_lsp_locations(method)
	if is_open() then
		return
	end
	state.lsp_locations = request_lsp_locations(method)
	if #state.lsp_locations == 0 then
		vim.notify("No locations found")
		return
	end

	if #state.lsp_locations == 1 then
		local entry = state.lsp_locations[1]
		vim.cmd("normal! m'")
		vim.cmd.edit(entry.filename)
		pcall(vim.api.nvim_win_set_cursor, 0, { entry.lnum, entry.col - 1 })
		return
	end

	state.last_picker = "lsp_locations"
	show(create_lsp_locations_output, false, false)
end

function M.setup()
	for name, hl in pairs(HIGHLIGHTS) do
		vim.api.nvim_set_hl(0, name, hl)
	end

	vim.api.nvim_create_user_command("FuzzyMagik", function(opts)
		local picker, option, value = unpack(opts.fargs)
		if picker == "find_files" and option == "show_all" and (value == "on" or value == "off") then
			find_files.show_all_files = value == "on"
		else
			vim.notify("Usage: :FuzzyMagik find_files show_all on|off", vim.log.levels.ERROR)
		end
	end, {
		nargs = "+",
		complete = function(arg_lead, cmd_line)
			local args = vim.split(cmd_line, "%s+")
			local options = ({ { "find_files" }, { "show_all" }, { "on", "off" } })[#args - 1] or {}
			return vim.tbl_filter(function(option)
				return vim.startswith(option, arg_lead)
			end, options)
		end,
	})
end

function M.find_files()
	if is_open() then
		return
	end
	state.last_picker = "find_files"
	find_files:show(is_open(), false, windows_service)
end

function M.live_grep()
	if is_open() then
		return
	end
	state.last_picker = "live_grep"
	show(create_grep_output, true, false)
end

function M.buffers()
	if is_open() then
		return
	end
	state.last_picker = "buffers"
	show(create_buffers_output, false, false)
end

function M.lsp_dynamic_workspace_symbols()
	if is_open() then
		return
	end
	state.last_picker = "lsp_dynamic_workspace_symbols"
	show(create_workspace_symbols_output, true, false)
end

function M.git_status()
	if is_open() then
		return
	end
	state.last_picker = "git_status"
	show(create_git_status_output, false, false)
end

function M.diagnostics()
	if is_open() then
		return
	end
	state.last_picker = "diagnostics"
	show(create_diagnostics_output, false, false)
end

function M.file_browser()
	if is_open() then
		return
	end
	state.last_picker = "file_browser"
	state.browser_dir = vim.fn.getcwd()
	show(create_file_browser_output, false, false)
end

function M.reveal()
	if is_open() then
		return
	end
	local file = vim.fn.expand("%:p")
	local dir = vim.fs.dirname(file)
	while vim.startswith(dir, vim.fn.getcwd() .. "/") do
		state.expanded[dir] = true
		dir = vim.fs.dirname(dir)
	end
	M.file_browser()
	for line, item in ipairs(results.items) do
		if item.path == file then
			vim.api.nvim_win_set_cursor(results.win, { line, 0 })
			break
		end
	end
end

function M.lsp_definitions()
	show_lsp_locations("textDocument/definition")
end

function M.lsp_references()
	show_lsp_locations("textDocument/references")
end

function M.resume()
	if state.last_picker == "find_files" then
		find_files:resume(is_open(), windows_service)
		return
	end
	if not state.list_output then
		return
	end
	show(state.list_output, state.start_insert, true)
end

return M
