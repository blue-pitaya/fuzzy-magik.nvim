local app_state = require("fuzzy-magik.app_state")
local WindowsService = require("fuzzy-magik.windows.windows_service")
local find_files = require("fuzzy-magik.pickers.find_files").new()
local live_grep = require("fuzzy-magik.pickers.live_grep").new()
local buffers = require("fuzzy-magik.pickers.buffers").new()
local workspace_symbols = require("fuzzy-magik.pickers.workspace_symbols").new()
local git_status = require("fuzzy-magik.pickers.git_status").new()
local diagnostics = require("fuzzy-magik.pickers.diagnostics").new()
local file_browser = require("fuzzy-magik.pickers.file_browser").new()
local lsp_locations = require("fuzzy-magik.pickers.lsp_locations").new()

local M = {}

local HIGHLIGHTS = {
	FuzzyMagikNormal = { link = "Normal" },
	FuzzyMagikBorder = { fg = "#767676" },
	FuzzyMagikBorderActive = { fg = "#00ffff" },
	FuzzyMagikMatch = { fg = "#00afd7", bold = true },
	FuzzyMagikExtension = { fg = "#b8bb26" },
	FuzzyMagikPath = { fg = "#bb9af7" },
	FuzzyMagikLineNr = { fg = "#767676" },
	FuzzyMagikKind = { fg = "#f2a475" },
	FuzzyMagikGitStaged = { fg = "#b8bb26" },
	FuzzyMagikGitUnstaged = { fg = "#e77969" },
	FuzzyMagikGitUntracked = { fg = "#767676" },
	FuzzyMagikMarked = { fg = "#ff64b5" },
}

---@class FuzzyMagikItem
---@field line string
---@field path string
---@field lnum? integer
---@field col? integer
---@field text? string
---@field bufnr? integer
---@field is_dir? boolean

local prompt = app_state.prompt
local results = app_state.results
local preview = app_state.preview
local state = app_state.state
local windows_service = WindowsService.new(prompt, results, preview)

local pickers = {
	find_files = find_files,
	live_grep = live_grep,
	buffers = buffers,
	lsp_dynamic_workspace_symbols = workspace_symbols,
	git_status = git_status,
	diagnostics = diagnostics,
	file_browser = file_browser,
	lsp_locations = lsp_locations,
}

local function is_open()
	return prompt.win ~= 0 and vim.api.nvim_win_is_valid(prompt.win)
end

function M.setup()
	for name, hl in pairs(HIGHLIGHTS) do
		vim.api.nvim_set_hl(0, name, hl)
	end

	vim.api.nvim_create_user_command("FuzzyMagik", function(opts)
		local picker, option, value = unpack(opts.fargs)
		if picker == "find_files" and option == "show_all" and (value == "on" or value == "off") then
			find_files.show_all_files = value == "on"
		else
			vim.notify("Usage: :FuzzyMagik find_files show_all on|off", vim.log.levels.ERROR)
		end
	end, {
		nargs = "+",
		complete = function(arg_lead, cmd_line)
			local args = vim.split(cmd_line, "%s+")
			local options = ({ { "find_files" }, { "show_all" }, { "on", "off" } })[#args - 1] or {}
			return vim.tbl_filter(function(option)
				return vim.startswith(option, arg_lead)
			end, options)
		end,
	})
end

function M.find_files()
	if is_open() then
		return
	end
	state.last_picker = "find_files"
	find_files:show(is_open(), false, windows_service)
end

function M.live_grep()
	if is_open() then
		return
	end
	state.last_picker = "live_grep"
	live_grep:show(is_open(), false, windows_service)
end

function M.live_grep_selection()
	if is_open() then
		return
	end
	local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
	vim.cmd.normal({ args = { "\27" }, bang = true })
	state.last_picker = "live_grep"
	live_grep:grep_text(is_open(), lines[1] or "", windows_service)
end

function M.buffers()
	if is_open() then
		return
	end
	state.last_picker = "buffers"
	buffers:show(is_open(), false, windows_service)
end

function M.lsp_dynamic_workspace_symbols()
	if is_open() then
		return
	end
	state.last_picker = "lsp_dynamic_workspace_symbols"
	workspace_symbols:show(is_open(), false, windows_service)
end

function M.git_status()
	if is_open() then
		return
	end
	state.last_picker = "git_status"
	git_status:show(is_open(), false, windows_service)
end

function M.diagnostics()
	if is_open() then
		return
	end
	state.last_picker = "diagnostics"
	diagnostics:show(is_open(), false, windows_service)
end

function M.file_browser()
	if is_open() then
		return
	end
	state.last_picker = "file_browser"
	file_browser:open(is_open(), windows_service)
end

function M.reveal()
	if is_open() then
		return
	end
	state.last_picker = "file_browser"
	file_browser:reveal(is_open(), windows_service)
end

function M.lsp_definitions()
	if lsp_locations:show_locations(is_open(), "textDocument/definition", windows_service) then
		state.last_picker = "lsp_locations"
	end
end

function M.lsp_references()
	if lsp_locations:show_locations(is_open(), "textDocument/references", windows_service) then
		state.last_picker = "lsp_locations"
	end
end

function M.resume()
	local picker = pickers[state.last_picker]
	if picker then
		picker:resume(is_open(), windows_service)
	end
end

return M
