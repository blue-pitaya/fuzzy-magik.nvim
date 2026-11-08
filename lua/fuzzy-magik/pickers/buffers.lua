local utils = require("fuzzy-magik.utils")

---@class Buffers
---@field items FuzzyMagikItem[]
---@field last_line integer
---@field windows_service WindowsService?
local Buffers = {}
Buffers.__index = Buffers

---@return Buffers
function Buffers.new()
	return setmetatable({
		items = {},
		last_line = -1,
	}, Buffers)
end

---@param pattern string
function Buffers:create_output(pattern)
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

---@param is_open boolean
---@param do_resume boolean
---@param windows_service WindowsService
function Buffers:show(is_open, do_resume, windows_service)
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

---@param is_open boolean
---@param windows_service WindowsService
function Buffers:resume(is_open, windows_service)
	self:show(is_open, true, windows_service)
end

function Buffers:set_autocmds()
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

function Buffers:set_keymaps()
	local prompt = self.windows_service.prompt
	local results = self.windows_service.results

	local function send_to_quickfix()
		self:send_to_quickfix()
	end

	vim.keymap.set({ "n", "i" }, "<C-q>", send_to_quickfix, { buffer = prompt.buf })

	vim.keymap.set("n", "<C-q>", send_to_quickfix, { buffer = results.buf })
	vim.keymap.set("n", "<CR>", function()
		local item = self.items[vim.api.nvim_win_get_cursor(0)[1]]
		if not item or not item.bufnr then
			return
		end
		self.windows_service:close()
		vim.cmd.buffer(item.bufnr)
	end, { buffer = results.buf })
end

---@param pattern string
function Buffers:update_results(pattern)
	utils.highlights = {}
	self.items = self:create_output(pattern)
	self.last_line = -1
	self.windows_service.results:render(self.items, utils.highlights)
end

---@param item FuzzyMagikItem
---@return boolean
function Buffers:is_current(item)
	return self.items[self.last_line] == item
end

---@param item FuzzyMagikItem
---@param lines string[]
function Buffers:set_preview_lines(item, lines)
	if self:is_current(item) then
		self.windows_service.preview:set_lines(lines)
	end
end

---@param item FuzzyMagikItem?
function Buffers:update_preview(item)
	if not item then
		return
	end

	if not item.bufnr then
		self:set_preview_lines(item, { "File not found: " .. item.path })
		return
	end

	if self:is_current(item) then
		local lines = vim.api.nvim_buf_get_lines(item.bufnr, 0, -1, false)
		self.windows_service.preview:show_lines(item.path, lines, vim.bo[item.bufnr].filetype)
	end
end

function Buffers:send_to_quickfix()
	local entries = {}
	for _, item in ipairs(self.items) do
		if item.bufnr then
			table.insert(entries, { bufnr = item.bufnr, lnum = 1 })
		end
	end
	self.windows_service:close()
	vim.cmd.stopinsert()
	vim.fn.setqflist(entries, "r")
	vim.cmd.copen()
end

return Buffers
