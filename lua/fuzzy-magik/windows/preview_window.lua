local utils = require("fuzzy-magik.utils")

local MIN_LINES = 500
local LINES_AFTER_MATCH = 100

---@class PreviewWindow
---@field win integer
---@field buf integer
local PreviewWindow = {}
PreviewWindow.__index = PreviewWindow

---@return PreviewWindow
function PreviewWindow.new()
	return setmetatable({
		win = 0,
		buf = 0,
	}, PreviewWindow)
end

function PreviewWindow:show()
	local width = math.floor(vim.o.columns * utils.WIDTH_RATIO)
	local start_col = math.floor((vim.o.columns - width) / 2)

	local height = vim.o.lines - utils.HEIGHT_MARGIN
	local results_width = math.floor(width * utils.RESULTS_WIDTH_RATIO)
	local preview_width = width - results_width - 1

	self.buf, self.win = utils.open_float({ buftype = "nofile", modifiable = false }, false, {
		width = preview_width,
		height = height,
		col = start_col + results_width + 1,
		row = utils.START_ROW,
		title = " Preview ",
		title_pos = "center",
	})
	vim.wo[self.win].number = false
	vim.wo[self.win].winhighlight = utils.WINHIGHLIGHT.default
end

---@param lines string[]
---@return boolean
function PreviewWindow:set_lines(lines)
	if not vim.api.nvim_win_is_valid(self.win) then
		return false
	end

	vim.treesitter.stop(self.buf)
	vim.bo[self.buf].modifiable = true
	vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
	vim.bo[self.buf].modifiable = false
	return true
end

---@param path string
---@param lines string[]
---@param lnum integer?
function PreviewWindow:show_file(path, lines, lnum)
	self:show_lines(path, lines, vim.filetype.match({ filename = path }), lnum)
end

---@param path string
---@param lines string[]
---@param ft string?
---@param lnum integer?
function PreviewWindow:show_lines(path, lines, ft, lnum)
	local limit = math.max(MIN_LINES, (lnum or 0) + LINES_AFTER_MATCH)
	if #lines > limit then
		lines = vim.list_slice(lines, 1, limit)
		table.insert(lines, "")
		table.insert(lines, "... (truncated)")
	end

	if not self:set_lines(lines) then
		return
	end

	local lang = ft and ft ~= "" and vim.treesitter.language.get_lang(ft)
	if lang then
		pcall(vim.treesitter.start, self.buf, lang)
	end

	vim.wo[self.win].cursorline = lnum ~= nil
	vim.api.nvim_win_set_cursor(self.win, { math.max(1, math.min(lnum or 1, #lines)), 0 })
	if lnum then
		vim.api.nvim_win_call(self.win, function()
			vim.cmd("normal! zz")
		end)
	end
	vim.api.nvim_win_set_config(self.win, {
		title = " " .. vim.fn.fnamemodify(path, ":t") .. " ",
		title_pos = "center",
	})
end

return PreviewWindow
