local utils = require("fuzzy-magik.utils")

local LSP_TIMEOUT_MS = 1000

---@class WorkspaceSymbols : Picker
---@field items FuzzyMagikItem[]
---@field last_line integer
---@field origin_buf integer
---@field windows_service WindowsService?
local WorkspaceSymbols = {}
WorkspaceSymbols.__index = WorkspaceSymbols

---@return WorkspaceSymbols
function WorkspaceSymbols.new()
	return setmetatable({
		items = {},
		last_line = -1,
		origin_buf = 0,
	}, WorkspaceSymbols)
end

---@param pattern string
function WorkspaceSymbols:create_output(pattern)
	local responses =
		vim.lsp.buf_request_sync(self.origin_buf, "workspace/symbol", { query = pattern }, LSP_TIMEOUT_MS)
	---@type FuzzyMagikItem[]
	local items = {}
	for client_id, response in pairs(responses or {}) do
		local client = vim.lsp.get_client_by_id(client_id)
		if client and response.result then
			local ok, symbols =
				pcall(vim.lsp.util.symbols_to_items, response.result, self.origin_buf, client.offset_encoding)
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

---@param do_resume boolean
---@param windows_service WindowsService
function WorkspaceSymbols:show(do_resume, windows_service)
	local resume_line = self.last_line
	self.origin_buf = vim.api.nvim_get_current_buf()
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
	self:update_results(prompt.text)
	local line = math.max(1, math.min(resume_line, #self.items))
	vim.api.nvim_set_current_win(results.win)
	vim.api.nvim_win_set_cursor(results.win, { line, 0 })
	self.last_line = line
	self:update_preview(self.items[line])
end

---@param windows_service WindowsService
function WorkspaceSymbols:resume(windows_service)
	self:show(true, windows_service)
end

function WorkspaceSymbols:set_autocmds()
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

function WorkspaceSymbols:set_keymaps()
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
function WorkspaceSymbols:update_results(pattern)
	utils.highlights = {}
	self.items = self:create_output(pattern)
	self.last_line = -1
	self.windows_service.results:render(self.items, utils.highlights)
end

---@param item FuzzyMagikItem
---@return boolean
function WorkspaceSymbols:is_current(item)
	return self.items[self.last_line] == item
end

---@param item FuzzyMagikItem
---@param lines string[]
function WorkspaceSymbols:set_preview_lines(item, lines)
	if self:is_current(item) then
		self.windows_service.preview:set_lines(lines)
	end
end

---@param item FuzzyMagikItem?
function WorkspaceSymbols:update_preview(item)
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

function WorkspaceSymbols:send_to_quickfix()
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

return WorkspaceSymbols
