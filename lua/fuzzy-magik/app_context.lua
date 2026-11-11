local PromptWindow = require("fuzzy-magik.windows.prompt_window")
local ResultsWindow = require("fuzzy-magik.windows.results_window")
local PreviewWindow = require("fuzzy-magik.windows.preview_window")
local WindowsService = require("fuzzy-magik.windows.windows_service")
local FindFiles = require("fuzzy-magik.pickers.find_files")
local LiveGrep = require("fuzzy-magik.pickers.live_grep")
local Buffers = require("fuzzy-magik.pickers.buffers")
local WorkspaceSymbols = require("fuzzy-magik.pickers.workspace_symbols")
local GitStatus = require("fuzzy-magik.pickers.git_status")
local Diagnostics = require("fuzzy-magik.pickers.diagnostics")
local FileBrowser = require("fuzzy-magik.pickers.file_browser")
local LspLocations = require("fuzzy-magik.pickers.lsp_locations")

---@class FuzzyMagikState
---@field last_picker string?

---@class AppContext
---@field prompt PromptWindow
---@field results ResultsWindow
---@field preview PreviewWindow
---@field windows_service WindowsService
---@field state FuzzyMagikState
---@field find_files FindFiles
---@field live_grep LiveGrep
---@field buffers Buffers
---@field workspace_symbols WorkspaceSymbols
---@field git_status GitStatus
---@field diagnostics Diagnostics
---@field file_browser FileBrowser
---@field lsp_locations LspLocations
---@field pickers table<string, Picker>
local AppContext = {}
AppContext.__index = AppContext

---@return AppContext
function AppContext.new()
	local prompt = PromptWindow.new()
	local results = ResultsWindow.new()
	local preview = PreviewWindow.new()
	local find_files = FindFiles.new()
	local live_grep = LiveGrep.new()
	local buffers = Buffers.new()
	local workspace_symbols = WorkspaceSymbols.new()
	local git_status = GitStatus.new()
	local diagnostics = Diagnostics.new()
	local file_browser = FileBrowser.new()
	local lsp_locations = LspLocations.new()
	return setmetatable({
		prompt = prompt,
		results = results,
		preview = preview,
		windows_service = WindowsService.new(prompt, results, preview),
		state = { last_picker = nil },
		find_files = find_files,
		live_grep = live_grep,
		buffers = buffers,
		workspace_symbols = workspace_symbols,
		git_status = git_status,
		diagnostics = diagnostics,
		file_browser = file_browser,
		lsp_locations = lsp_locations,
		pickers = {
			find_files = find_files,
			live_grep = live_grep,
			buffers = buffers,
			lsp_dynamic_workspace_symbols = workspace_symbols,
			git_status = git_status,
			diagnostics = diagnostics,
			file_browser = file_browser,
			lsp_locations = lsp_locations,
		},
	}, AppContext)
end

return AppContext
