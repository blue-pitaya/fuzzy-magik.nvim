local utils = require("fuzzy-magik.utils")

---@class PromptWindow
---@field win integer
---@field buf integer
---@field text string
local PromptWindow = {}
PromptWindow.__index = PromptWindow

---@return PromptWindow
function PromptWindow.new()
	return setmetatable({
		win = 0,
		buf = 0,
		text = "",
	}, PromptWindow)
end

function PromptWindow:show()
	local width = math.floor(vim.o.columns * utils.WIDTH_RATIO)
	local start_col = math.floor((vim.o.columns - width) / 2)

	self.buf, self.win = utils.open_float({ buftype = "prompt", bufhidden = "wipe" }, true, {
		width = width,
		height = 1,
		row = 1,
		col = start_col,
		style = "minimal",
	})
	vim.fn.prompt_setprompt(self.buf, utils.PROMPT)
	vim.wo[self.win].winhighlight = utils.WINHIGHLIGHT.active
end

---@return string
function PromptWindow:read_text()
	local text = vim.api.nvim_buf_get_lines(self.buf, 0, 1, false)[1]
	self.text = text:gsub("^" .. vim.pesc(utils.PROMPT), "")
	return self.text
end

function PromptWindow:write_text()
	vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, { utils.PROMPT .. self.text })
end

return PromptWindow
