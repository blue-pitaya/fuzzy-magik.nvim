local utils = require("fuzzy-magik.utils")

local NAMESPACE = vim.api.nvim_create_namespace("tree_highlights")

---@class ResultsWindow
---@field win integer
---@field buf integer
---@field items FuzzyMagikItem[]
---@field last_line integer
local ResultsWindow = {}
ResultsWindow.__index = ResultsWindow

---@return ResultsWindow
function ResultsWindow.new()
	return setmetatable({
		win = 0,
		buf = 0,
		items = {},
		last_line = -1,
	}, ResultsWindow)
end

function ResultsWindow:show()
	local width = math.floor(vim.o.columns * utils.WIDTH_RATIO)
	local start_col = math.floor((vim.o.columns - width) / 2)

	local height = vim.o.lines - utils.HEIGHT_MARGIN
	local results_width = math.floor(width * utils.RESULTS_WIDTH_RATIO)

	self.buf, self.win = utils.open_float({ buftype = "nofile", bufhidden = "wipe", modifiable = false }, false, {
		width = results_width - 1,
		height = height,
		row = utils.START_ROW,
		col = start_col,
		style = "minimal",
	})
	vim.wo[self.win].cursorline = true
	vim.wo[self.win].winhighlight = utils.WINHIGHLIGHT.default
end

---@param items FuzzyMagikItem[]
---@param highlights table[]
function ResultsWindow:render(items, highlights)
	local lines = {}
	for _, item in ipairs(items) do
		table.insert(lines, item.line)
	end

	vim.bo[self.buf].modifiable = true
	vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)

	vim.api.nvim_buf_clear_namespace(self.buf, NAMESPACE, 0, -1)
	for _, hl in ipairs(highlights) do
		vim.api.nvim_buf_set_extmark(self.buf, NAMESPACE, hl.line, hl.col_start, {
			end_col = hl.col_end,
			hl_group = hl.hl_group,
		})
	end

	vim.bo[self.buf].modifiable = false
end

return ResultsWindow
