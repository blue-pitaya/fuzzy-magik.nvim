local utils = require("fuzzy-magik.utils")

local LSP_TIMEOUT_MS = 1000

---@class LspLocations : Picker
---@field items FuzzyMagikItem[]
---@field last_line integer
---@field locations table[]
---@field windows_service WindowsService?
local LspLocations = {}
LspLocations.__index = LspLocations

---@return LspLocations
function LspLocations.new()
	return setmetatable({
		items = {},
		last_line = -1,
		locations = {},
	}, LspLocations)
end

---@param pattern string
function LspLocations:create_output(pattern)
	---@type FuzzyMagikItem[]
	local items = {}
	for _, entry in ipairs(self.locations) do
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

---@param method string
function LspLocations:request_locations(method)
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

---@param method string
---@param windows_service WindowsService
---@return boolean
function LspLocations:show_locations(method, windows_service)
	self.locations = self:request_locations(method)
	if #self.locations == 0 then
		vim.notify("No locations found")
		return false
	end

	if #self.locations == 1 then
		local entry = self.locations[1]
		vim.cmd("normal! m'")
		vim.cmd.edit(entry.filename)
		pcall(vim.api.nvim_win_set_cursor, 0, { entry.lnum, entry.col - 1 })
		return false
	end

	self:show(false, windows_service)
	return true
end

---@param do_resume boolean
---@param windows_service WindowsService
function LspLocations:show(do_resume, windows_service)
	local resume_line = self.last_line
	self.last_line = -1
	self.items = {}

	self.windows_service = windows_service
	windows_service:open()
	self:set_autocmds()
	self:set_keymaps()
	windows_service:set_autocmds()
	windows_service:set_keymaps()

	local prompt = windows_service.prompt
	local results = windows_service.results
	local line = 1
	if do_resume then
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

---@param windows_service WindowsService
function LspLocations:resume(windows_service)
	self:show(true, windows_service)
end

function LspLocations:set_autocmds()
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

function LspLocations:set_keymaps()
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
function LspLocations:update_results(pattern)
	utils.highlights = {}
	self.items = self:create_output(pattern)
	self.last_line = -1
	self.windows_service.results:render(self.items, utils.highlights)
end

---@param item FuzzyMagikItem
---@return boolean
function LspLocations:is_current(item)
	return self.items[self.last_line] == item
end

---@param item FuzzyMagikItem
---@param lines string[]
function LspLocations:set_preview_lines(item, lines)
	if self:is_current(item) then
		self.windows_service.preview:set_lines(lines)
	end
end

---@param item FuzzyMagikItem?
function LspLocations:update_preview(item)
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

function LspLocations:send_to_quickfix()
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

return LspLocations
