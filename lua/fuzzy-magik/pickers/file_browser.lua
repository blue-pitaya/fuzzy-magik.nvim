local utils = require("fuzzy-magik.utils")

---@class FileBrowser
---@field items FuzzyMagikItem[]
---@field last_line integer
---@field prompt_text string
---@field browser_dir string?
---@field expanded table<string, boolean>
---@field marked table<string, boolean>
---@field clipboard { action: string?, paths: string[] }
---@field windows_service WindowsService?
local FileBrowser = {}
FileBrowser.__index = FileBrowser

---@return FileBrowser
function FileBrowser.new()
	return setmetatable({
		items = {},
		last_line = -1,
		prompt_text = "",
		browser_dir = nil,
		expanded = {},
		marked = {},
		clipboard = {
			action = nil,
			paths = {},
		},
	}, FileBrowser)
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

---@param dir string
---@param depth integer
---@param entries table[]
function FileBrowser:collect_tree_entries(dir, depth, entries)
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
		if child.is_dir and self.expanded[child.path] then
			self:collect_tree_entries(child.path, depth + 1, entries)
		end
	end
end

---@param pattern string
function FileBrowser:create_output(pattern)
	local entries = {}
	self:collect_tree_entries(self.browser_dir, 0, entries)

	---@type FuzzyMagikItem[]
	local items = {}
	for _, entry in ipairs(entries) do
		local name = entry.is_dir and entry.name .. "/" or entry.name
		local cols = utils.fuzzy_match_cols(name, pattern)
		if cols then
			local line = #items
			local mark = self.marked[entry.path] and "+ " or "  "
			local icon = "  "
			if entry.is_dir then
				icon = self.expanded[entry.path] and "▾ " or "▸ "
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

---@param is_open boolean
---@param do_resume boolean
---@param windows_service WindowsService
function FileBrowser:show(is_open, do_resume, windows_service)
	if is_open then
		return
	end

	local resume_line = self.last_line
	self.last_line = -1
	self.items = {}

	self.windows_service = windows_service
	windows_service:open()
	self:set_autocmds()
	self:set_keymaps()
	self:set_title()
	windows_service:set_autocmds()
	windows_service:set_keymaps()

	local prompt = windows_service.prompt
	local results = windows_service.results
	local line = 1
	if do_resume then
		prompt.text = self.prompt_text
		prompt:write_text()
		self:update_results(prompt.text)
		line = math.max(1, math.min(resume_line, #self.items))
	else
		prompt.text = ""
		self:update_results("")
	end
	vim.api.nvim_set_current_win(results.win)
	vim.api.nvim_win_set_cursor(results.win, { line, 0 })
	self.last_line = line
	self:update_preview(self.items[line])
end

---@param is_open boolean
---@param windows_service WindowsService
function FileBrowser:resume(is_open, windows_service)
	self:show(is_open, true, windows_service)
end

---@param is_open boolean
---@param windows_service WindowsService
function FileBrowser:open(is_open, windows_service)
	if not self.browser_dir then
		self:open_cwd(is_open, windows_service)
		return
	end
	self:show(is_open, true, windows_service)
end

---@param is_open boolean
---@param windows_service WindowsService
function FileBrowser:open_cwd(is_open, windows_service)
	if is_open then
		return
	end
	self.browser_dir = vim.fn.getcwd()
	self:show(is_open, false, windows_service)
end

---@param is_open boolean
---@param windows_service WindowsService
function FileBrowser:reveal(is_open, windows_service)
	if is_open then
		return
	end
	local file = vim.fn.expand("%:p")
	local dir = vim.fs.dirname(file)
	while vim.startswith(dir, vim.fn.getcwd() .. "/") do
		self.expanded[dir] = true
		dir = vim.fs.dirname(dir)
	end
	self:open_cwd(is_open, windows_service)
	for line, item in ipairs(self.items) do
		if item.path == file then
			vim.api.nvim_win_set_cursor(windows_service.results.win, { line, 0 })
			break
		end
	end
end

function FileBrowser:set_autocmds()
	local prompt = self.windows_service.prompt
	local results = self.windows_service.results

	local function on_results_cursor()
		local line = vim.api.nvim_win_get_cursor(0)[1]
		if line ~= self.last_line then
			self.last_line = line
			self:update_preview(self.items[line])
		end
	end

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = prompt.buf,
		callback = function()
			self:update_results(prompt:read_text())
		end,
	})

	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = results.buf,
		callback = on_results_cursor,
	})

	vim.api.nvim_create_autocmd("WinEnter", {
		buffer = results.buf,
		callback = on_results_cursor,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(results.win),
		callback = function()
			self.last_line = vim.api.nvim_win_get_cursor(results.win)[1]
		end,
		once = true,
	})
end

function FileBrowser:set_keymaps()
	local prompt = self.windows_service.prompt
	local results = self.windows_service.results

	local function send_to_quickfix()
		self:send_to_quickfix()
	end

	local function close()
		self.windows_service:close()
		vim.cmd.stopinsert()
	end

	vim.keymap.set({ "n", "i" }, "<C-q>", send_to_quickfix, { buffer = prompt.buf })
	vim.keymap.set({ "n", "i" }, "<C-n>", close, { buffer = prompt.buf })

	vim.keymap.set("n", "<C-q>", send_to_quickfix, { buffer = results.buf })
	vim.keymap.set("n", "<C-n>", close, { buffer = results.buf })
	vim.keymap.set("n", "<CR>", function()
		local item = self.items[vim.api.nvim_win_get_cursor(0)[1]]
		if not item or item.path == "" then
			return
		end
		if item.is_dir then
			self.expanded[item.path] = not self.expanded[item.path] or nil
			self:refresh()
			return
		end
		self.windows_service:close()
		vim.cmd.edit(item.path)
	end, { buffer = results.buf })

	vim.keymap.set("n", "-", function()
		self.expanded[self.browser_dir] = true
		self:open_dir(vim.fs.dirname(self.browser_dir))
	end, { buffer = results.buf })
	vim.keymap.set("n", "o", "<CR>", { buffer = results.buf, remap = true })
	vim.keymap.set("n", "<Tab>", function()
		self:toggle_mark()
	end, { buffer = results.buf })
	vim.keymap.set("n", "x", function()
		self:set_clipboard("cut")
	end, { buffer = results.buf })
	vim.keymap.set("n", "y", function()
		self:set_clipboard("copy")
	end, { buffer = results.buf })
	vim.keymap.set("n", "p", function()
		self:paste_clipboard()
	end, { buffer = results.buf })
	vim.keymap.set("n", "d", function()
		self:delete_selected()
	end, { buffer = results.buf })
	vim.keymap.set("n", "r", function()
		self:rename_current()
	end, { buffer = results.buf })
	vim.keymap.set("n", "a", function()
		self:create_path()
	end, { buffer = results.buf })
end

---@param pattern string
function FileBrowser:update_results(pattern)
	utils.highlights = {}
	self.prompt_text = pattern
	self.items = self:create_output(pattern)
	self.last_line = -1
	self.windows_service.results:render(self.items, utils.highlights)
end

---@param item FuzzyMagikItem
---@return boolean
function FileBrowser:is_current(item)
	return self.items[self.last_line] == item
end

---@param item FuzzyMagikItem
---@param lines string[]
function FileBrowser:set_preview_lines(item, lines)
	if self:is_current(item) then
		self.windows_service.preview:set_lines(lines)
	end
end

---@param item FuzzyMagikItem?
function FileBrowser:update_preview(item)
	if not item then
		return
	end

	if item.is_dir then
		local lines = {}
		for name, entry_type in vim.fs.dir(item.path) do
			table.insert(lines, entry_type == "directory" and name .. "/" or name)
		end
		table.sort(lines)
		if self:is_current(item) then
			self.windows_service.preview:show_lines(item.path, lines, nil)
		end
		return
	end

	if vim.fn.filereadable(item.path) == 0 then
		self:set_preview_lines(item, { "File not found: " .. item.path })
		return
	end

	local function show_read_error()
		vim.schedule(function()
			self:set_preview_lines(item, { "Error reading file" })
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
					if not self:is_current(item) then
						return
					end
					local lines = vim.split(data, "\n")
					if lines[#lines] == "" then
						table.remove(lines)
					end
					self.windows_service.preview:show_file(item.path, lines)
				end)
			end)
		end)
	end)
end

function FileBrowser:send_to_quickfix()
	local entries = {}
	for _, item in ipairs(self.items) do
		if item.path ~= "" then
			table.insert(entries, { filename = item.path, lnum = 1 })
		end
	end
	self.windows_service:close()
	vim.cmd.stopinsert()
	vim.fn.setqflist(entries, "r")
	vim.cmd.copen()
end

function FileBrowser:current_item()
	return self.items[vim.api.nvim_win_get_cursor(self.windows_service.results.win)[1]]
end

function FileBrowser:target_dir()
	local item = self:current_item()
	if item.path == "" then
		return self.browser_dir
	end
	return vim.fs.dirname(item.path)
end

function FileBrowser:selected_paths()
	local paths = vim.tbl_keys(self.marked)
	if #paths > 0 then
		table.sort(paths)
		return paths
	end

	local item = self:current_item()
	if item.path == "" then
		return {}
	end
	return { item.path }
end

function FileBrowser:set_title()
	vim.api.nvim_win_set_config(self.windows_service.results.win, {
		title = " " .. vim.fn.fnamemodify(self.browser_dir, ":~") .. " ",
		title_pos = "center",
	})
end

function FileBrowser:refresh()
	local results = self.windows_service.results
	self:set_title()
	self:update_results(self.windows_service.prompt.text)
	local line = vim.api.nvim_win_get_cursor(results.win)[1]
	self.last_line = line
	self:update_preview(self.items[line])
end

---@param dir string
function FileBrowser:open_dir(dir)
	local prompt = self.windows_service.prompt
	self.browser_dir = dir
	prompt.text = ""
	prompt:write_text()
	vim.api.nvim_win_set_cursor(self.windows_service.results.win, { 1, 0 })
	self:refresh()
end

function FileBrowser:toggle_mark()
	local item = self:current_item()
	if item.path == "" then
		return
	end

	self.marked[item.path] = not self.marked[item.path] or nil
	self:refresh()
end

---@param action string
function FileBrowser:set_clipboard(action)
	local paths = self:selected_paths()
	if #paths == 0 then
		return
	end

	self.clipboard = { action = action, paths = paths }
	self.marked = {}
	self:refresh()
	vim.notify(action:sub(1, 1):upper() .. action:sub(2) .. ": " .. #paths .. " item(s)")
end

function FileBrowser:paste_clipboard()
	local dir = self:target_dir()
	self.expanded[dir] = true
	for _, path in ipairs(self.clipboard.paths) do
		local target = vim.fs.joinpath(dir, vim.fs.basename(path))
		if vim.uv.fs_stat(target) then
			vim.notify("Already exists: " .. target, vim.log.levels.WARN)
		elseif vim.startswith(dir .. "/", path .. "/") then
			vim.notify("Cannot paste into itself: " .. path, vim.log.levels.WARN)
		elseif self.clipboard.action == "cut" then
			move_path(path, target)
		else
			copy_path(path, target)
		end
	end
	if self.clipboard.action == "cut" then
		self.clipboard = { action = nil, paths = {} }
	end
	self:refresh()
end

function FileBrowser:delete_selected()
	local paths = self:selected_paths()
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
	self.marked = {}
	self:refresh()
end

function FileBrowser:rename_current()
	local item = self:current_item()
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
	self:refresh()
end

function FileBrowser:create_path()
	local name = vim.fn.input("Create: ")
	if name == "" then
		return
	end

	local dir = self:target_dir()
	local path = vim.fs.joinpath(dir, name)
	if vim.uv.fs_stat(path) then
		vim.notify("Already exists: " .. path, vim.log.levels.WARN)
		return
	end

	self.expanded[dir] = true
	if vim.endswith(name, "/") then
		vim.fn.mkdir(path, "p")
	else
		vim.fn.mkdir(vim.fs.dirname(path), "p")
		vim.fn.writefile({}, path)
	end
	self:refresh()
end

return FileBrowser
