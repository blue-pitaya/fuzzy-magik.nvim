local utils = require("fuzzy-magik.utils")

---@class WindowsService
---@field prompt PromptWindow
---@field results ResultsWindow
---@field preview PreviewWindow
---@field origin_win integer
local WindowsService = {}
WindowsService.__index = WindowsService

---@param prompt PromptWindow
---@param results ResultsWindow
---@param preview PreviewWindow
---@return WindowsService
function WindowsService.new(prompt, results, preview)
	return setmetatable({
		prompt = prompt,
		results = results,
		preview = preview,
		origin_win = 0,
	}, WindowsService)
end

function WindowsService:open()
	self.origin_win = vim.api.nvim_get_current_win()
	self.prompt:show()
	self.results:show()
	self.preview:show()
end

function WindowsService:close()
	local current = vim.api.nvim_get_current_win()
	local was_focused = current == self.prompt.win or current == self.results.win or current == self.preview.win
	for _, window in ipairs({ self.prompt, self.results, self.preview }) do
		if vim.api.nvim_win_is_valid(window.win) then
			vim.api.nvim_win_close(window.win, true)
		end
	end
	if was_focused and vim.api.nvim_win_is_valid(self.origin_win) then
		vim.api.nvim_set_current_win(self.origin_win)
	end
end

function WindowsService:set_autocmds()
	for _, window in ipairs({ self.prompt, self.results, self.preview }) do
		vim.api.nvim_create_autocmd("WinClosed", {
			pattern = tostring(window.win),
			callback = function()
				self:close()
			end,
			once = true,
		})
		vim.api.nvim_create_autocmd("WinEnter", {
			buffer = window.buf,
			callback = function()
				vim.wo[window.win].winhighlight = utils.WINHIGHLIGHT.active
			end,
		})
		vim.api.nvim_create_autocmd("WinLeave", {
			buffer = window.buf,
			callback = function()
				vim.wo[window.win].winhighlight = utils.WINHIGHLIGHT.default
				vim.schedule(function()
					local win = vim.api.nvim_get_current_win()
					if win ~= self.prompt.win and win ~= self.results.win and win ~= self.preview.win then
						self:close()
					end
				end)
			end,
		})
	end
end

function WindowsService:set_keymaps()
	local function focus_results()
		vim.api.nvim_set_current_win(self.results.win)
	end

	vim.keymap.set({ "n", "i" }, "<Esc>", focus_results, { buffer = self.prompt.buf })
	vim.keymap.set({ "n", "i" }, "<CR>", focus_results, { buffer = self.prompt.buf })

	vim.keymap.set("n", "<Esc>", function()
		self:close()
	end, { buffer = self.results.buf })
	vim.keymap.set("n", "i", function()
		vim.api.nvim_set_current_win(self.prompt.win)
		vim.cmd.startinsert({ bang = true })
	end, { buffer = self.results.buf })
end

return WindowsService
