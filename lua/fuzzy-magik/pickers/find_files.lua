local utils = require("fuzzy-magik.utils")

---@class FindFiles
---@field files string[]?
---@field show_all_files boolean
---@field win integer
---@field buf integer
---@field items FuzzyMagikItem[]
---@field last_line integer
---@field windows_service WindowsService?
local FindFiles = {}
FindFiles.__index = FindFiles

---@return FindFiles
function FindFiles.new()
	return setmetatable({
		files = nil,
		show_all_files = false,
		win = 0,
		buf = 0,
		items = {},
		last_line = -1,
	}, FindFiles)
end

---@param pattern string
function FindFiles:create_output(pattern)
	if not self.files then
		local cmd = { "rg", "--files" }
		if self.show_all_files then
			table.insert(cmd, "--no-ignore-vcs")
			table.insert(cmd, "--hidden")
		end
		local result = vim.system(cmd, { text = true }):wait()
		self.files = vim.split(result.stdout or "", "\n", { trimempty = true })
		table.sort(self.files)
	end

	local lower_pattern = pattern:lower()
	local matches = {}
	for _, filepath in ipairs(self.files) do
		local cols = utils.fuzzy_match_cols(filepath, pattern)
		if cols then
			local lower_path = filepath:lower()
			local name_col = lower_path:match("()[^/]*$")
			local name = lower_path:sub(name_col)
			local rank = 3
			local start = nil
			if name == lower_pattern then
				rank = 0
				start = name_col
			else
				local name_start = name:find(lower_pattern, 1, true)
				if name_start then
					rank = 1
					start = name_col + name_start - 1
				else
					start = lower_path:find(lower_pattern, 1, true)
					if start then
						rank = 2
					end
				end
			end
			if start and pattern ~= "" then
				cols = {}
				for col = start, start + #pattern - 1 do
					table.insert(cols, col)
				end
			end
			table.insert(matches, { filepath = filepath, cols = cols, rank = rank })
		end
	end
	table.sort(matches, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.filepath < b.filepath
	end)

	---@type FuzzyMagikItem[]
	local items = {}
	for _, match in ipairs(matches) do
		local line = #items
		utils.add_path_highlights(line, 0, match.filepath)
		utils.add_match_highlights(line, 0, match.cols)
		table.insert(items, { line = match.filepath, path = match.filepath })
	end

	if #items == 0 then
		return utils.message("No files found matching pattern: " .. pattern)
	end
	return items
end

---@param is_open boolean
---@param do_resume boolean
---@param windows_service WindowsService
function FindFiles:show(is_open, do_resume, windows_service)
	if is_open then
		return
	end

	local resume_line = self.last_line
	self.files = nil
	self.last_line = -1
	self.items = {}

	self.windows_service = windows_service
	windows_service:open()
	self:set_autocmds()
	windows_service:set_autocmds()
	windows_service:set_keymaps()
	self:set_keymaps()

	if not do_resume then
		vim.cmd.startinsert()
		return
	end

	local prompt = windows_service.prompt
	local results = windows_service.results
	prompt:write_text()
	self:update_results(prompt.text)
	local line = math.max(1, math.min(resume_line, #self.items))
	vim.api.nvim_set_current_win(results.win)
	vim.api.nvim_win_set_cursor(results.win, { line, 0 })
	self.last_line = line
	self:update_preview(self.items[line])
end

---@param is_open boolean
---@param windows_service WindowsService
function FindFiles:resume(is_open, windows_service)
	self:show(is_open, true, windows_service)
end

function FindFiles:set_autocmds()
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
end

function FindFiles:set_keymaps()
	local prompt = self.windows_service.prompt
	local results = self.windows_service.results

	local function send_to_quickfix()
		self:send_to_quickfix()
	end

	vim.keymap.set({ "n", "i" }, "<C-q>", send_to_quickfix, { buffer = prompt.buf })
	vim.keymap.set({ "n", "i" }, "<CR>", function()
		vim.cmd.stopinsert()
		self:open_item(self.items[vim.api.nvim_win_get_cursor(results.win)[1]])
	end, { buffer = prompt.buf })

	vim.keymap.set("n", "<C-q>", send_to_quickfix, { buffer = results.buf })
	vim.keymap.set("n", "<CR>", function()
		self:open_item(self.items[vim.api.nvim_win_get_cursor(0)[1]])
	end, { buffer = results.buf })
end

---@param item FuzzyMagikItem?
function FindFiles:open_item(item)
	if not item or item.path == "" then
		return
	end
	self.windows_service:close()
	vim.cmd.edit(item.path)
end

---@param pattern string
function FindFiles:update_results(pattern)
	utils.highlights = {}
	self.items = self:create_output(pattern)
	self.last_line = -1
	self.windows_service.results:render(self.items, utils.highlights)
end

---@param item FuzzyMagikItem
---@return boolean
function FindFiles:is_current(item)
	return self.items[self.last_line] == item
end

---@param item FuzzyMagikItem
---@param lines string[]
function FindFiles:set_preview_lines(item, lines)
	if self:is_current(item) then
		self.windows_service.preview:set_lines(lines)
	end
end

---@param item FuzzyMagikItem?
function FindFiles:update_preview(item)
	if not item then
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

function FindFiles:send_to_quickfix()
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

return FindFiles
