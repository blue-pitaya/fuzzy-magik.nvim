local utils = require("fuzzy-magik.utils")

---@class LiveGrep : Picker
---@field items FuzzyMagikItem[]
---@field last_line integer
---@field windows_service WindowsService?
---@field job vim.SystemObj?
---@field request integer
local LiveGrep = {}
LiveGrep.__index = LiveGrep

---@return LiveGrep
function LiveGrep.new()
	return setmetatable({
		items = {},
		last_line = -1,
		job = nil,
		request = 0,
	}, LiveGrep)
end

function LiveGrep:stop_job()
	self.request = self.request + 1
	if self.job and not self.job:is_closing() then
		self.job:kill(15)
	end
	self.job = nil
end

---@param output string
function LiveGrep:append_output(output)
	local results = self.windows_service.results
	if not vim.api.nvim_buf_is_valid(results.buf) then
		return
	end

	local start_line = #self.items
	utils.highlights = {}
	---@type FuzzyMagikItem[]
	local batch = {}
	for output_line in vim.gsplit(output, "\n", { plain = true }) do
		local filepath, lnum, col, text = output_line:match("^(.-):(%d+):(%d+):(.*)$")
		if filepath then
			local line = start_line + #batch
			local location = ":" .. lnum .. ":" .. col .. ":"
			utils.add_path_highlights(line, 0, filepath)
			table.insert(utils.highlights, {
				line = line,
				col_start = #filepath,
				col_end = #filepath + #location,
				hl_group = "FuzzyMagikLineNr",
			})
			local item = {
				line = filepath .. location .. text,
				path = filepath,
				lnum = tonumber(lnum),
				col = tonumber(col),
				text = text,
			}
			table.insert(batch, item)
			table.insert(self.items, item)
		end
	end

	if #batch > 0 then
		results:render(batch, utils.highlights, start_line)
	end
end

---@param items FuzzyMagikItem[]
function LiveGrep:show_message_items(items)
	self.items = items
	if vim.api.nvim_buf_is_valid(self.windows_service.results.buf) then
		self.windows_service.results:render(items, {})
	end
end

---@param do_resume boolean
---@param windows_service WindowsService
function LiveGrep:show(do_resume, windows_service)
	local resume_line = self.last_line
	self.last_line = -1
	self.items = {}

	self.windows_service = windows_service
	windows_service:open()
	self:set_autocmds()
	self:set_keymaps()
	windows_service:set_autocmds()
	windows_service:set_keymaps()

	if not do_resume then
		vim.cmd.startinsert()
		return
	end

	local prompt = windows_service.prompt
	local results = windows_service.results
	prompt:write_text()
	vim.api.nvim_set_current_win(results.win)
	self:update_results(prompt.text, function()
		if not vim.api.nvim_win_is_valid(results.win) then
			return
		end
		local line = math.max(1, math.min(resume_line, #self.items))
		vim.api.nvim_win_set_cursor(results.win, { line, 0 })
		self.last_line = line
		self:update_preview(self.items[line])
	end)
end

---@param windows_service WindowsService
function LiveGrep:resume(windows_service)
	self:show(true, windows_service)
end

---@param text string
---@param windows_service WindowsService
function LiveGrep:grep_text(text, windows_service)
	self:show(false, windows_service)
	windows_service.prompt.text = text
	windows_service.prompt:write_text()
	self:update_results(text)
	vim.cmd.startinsert({ bang = true })
end

function LiveGrep:set_autocmds()
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

	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = results.buf,
		callback = function()
			self:stop_job()
		end,
	})
end

function LiveGrep:set_keymaps()
	local prompt = self.windows_service.prompt
	local results = self.windows_service.results

	local function send_to_quickfix()
		self:send_to_quickfix()
	end

	vim.keymap.set({ "n", "i" }, "<C-q>", send_to_quickfix, { buffer = prompt.buf })

	vim.keymap.set("n", "<C-q>", send_to_quickfix, { buffer = results.buf })
	vim.keymap.set("n", "<CR>", function()
		local item = self.items[vim.api.nvim_win_get_cursor(0)[1]]
		if not item or item.path == "" then
			return
		end
		self.windows_service:close()
		vim.cmd.edit(item.path)
		pcall(vim.api.nvim_win_set_cursor, 0, { item.lnum, (item.col or 1) - 1 })
	end, { buffer = results.buf })
end

---@param pattern string
---@param on_done fun()?
function LiveGrep:update_results(pattern, on_done)
	self:stop_job()
	local request = self.request
	self.items = {}
	self.last_line = -1

	if pattern == "" then
		self:show_message_items(utils.message(""))
		if on_done then
			on_done()
		end
		return
	end

	local cmd = {
		"rg",
		"--with-filename",
		"--line-number",
		"--column",
		"--no-heading",
		"--color=never",
		"--smart-case",
		"--max-columns=500",
		"--max-columns-preview",
		"--",
		pattern,
	}

	local pending = ""
	self.job = vim.system(cmd, {
		text = true,
		stdout = function(_, data)
			if not data then
				return
			end
			local chunk = pending .. data
			local last_newline = chunk:match(".*()\n")
			if not last_newline then
				pending = chunk
				return
			end
			pending = chunk:sub(last_newline + 1)
			local output = chunk:sub(1, last_newline - 1)
			vim.schedule(function()
				if request == self.request then
					self:append_output(output)
				end
			end)
		end,
	}, function()
		vim.schedule(function()
			if request ~= self.request then
				return
			end
			self.job = nil
			if pending ~= "" then
				self:append_output(pending)
			end
			if #self.items == 0 then
				self:show_message_items(utils.message("No matches for pattern: " .. pattern))
			end
			if on_done then
				on_done()
			end
		end)
	end)
end

---@param item FuzzyMagikItem
---@return boolean
function LiveGrep:is_current(item)
	return self.items[self.last_line] == item
end

---@param item FuzzyMagikItem
---@param lines string[]
function LiveGrep:set_preview_lines(item, lines)
	if self:is_current(item) then
		self.windows_service.preview:set_lines(lines)
	end
end

---@param item FuzzyMagikItem?
function LiveGrep:update_preview(item)
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
					self.windows_service.preview:show_file(item.path, lines, item.lnum)
				end)
			end)
		end)
	end)
end

function LiveGrep:send_to_quickfix()
	local entries = {}
	for _, item in ipairs(self.items) do
		if item.path ~= "" then
			table.insert(entries, { filename = item.path, lnum = item.lnum, col = item.col, text = item.text })
		end
	end
	self.windows_service:close()
	vim.cmd.stopinsert()
	vim.fn.setqflist(entries, "r")
	vim.cmd.copen()
end

return LiveGrep
