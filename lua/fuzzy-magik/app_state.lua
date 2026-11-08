local PromptWindow = require("fuzzy-magik.windows.prompt_window")
local ResultsWindow = require("fuzzy-magik.windows.results_window")
local PreviewWindow = require("fuzzy-magik.windows.preview_window")

local M = {}

M.prompt = PromptWindow.new()
M.results = ResultsWindow.new()
M.preview = PreviewWindow.new()
M.state = {
	origin_buf = 0,
	last_picker = nil,
	list_output = nil,
	start_insert = nil,
	lsp_locations = nil,
	browser_dir = nil,
	expanded = {},
	marked = {},
	clipboard = {
		action = nil,
		paths = {},
	},
}

return M
