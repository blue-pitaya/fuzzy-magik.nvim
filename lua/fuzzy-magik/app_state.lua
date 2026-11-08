local PromptWindow = require("fuzzy-magik.windows.prompt_window")
local ResultsWindow = require("fuzzy-magik.windows.results_window")
local PreviewWindow = require("fuzzy-magik.windows.preview_window")

local M = {}

M.prompt = PromptWindow.new()
M.results = ResultsWindow.new()
M.preview = PreviewWindow.new()
M.state = {
	last_picker = nil,
}

return M
