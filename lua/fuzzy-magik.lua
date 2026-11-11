local AppContext = require("fuzzy-magik.app_context")

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

---@class Picker
---@field show fun(self: Picker, do_resume: boolean, windows_service: WindowsService)
---@field resume fun(self: Picker, windows_service: WindowsService)

---@type AppContext?
local app_context

---@return AppContext?
local function get_app_context()
	if not app_context then
		vim.notify("FuzzyMagik: call setup() first", vim.log.levels.ERROR)
	end
	return app_context
end

---@param app AppContext
local function is_open(app)
	return app.prompt.win ~= 0 and vim.api.nvim_win_is_valid(app.prompt.win)
end

---@param name string
---@param open fun(app: AppContext)
local function open_picker(name, open)
	local app = get_app_context()
	if not app or is_open(app) then
		return
	end
	app.state.last_picker = name
	open(app)
end

function M.setup()
	app_context = AppContext.new()

	for name, hl in pairs(HIGHLIGHTS) do
		vim.api.nvim_set_hl(0, name, hl)
	end

	vim.api.nvim_create_user_command("FuzzyMagik", function(opts)
		local app = get_app_context()
		if not app then
			return
		end
		local picker, option, value = unpack(opts.fargs)
		if picker == "find_files" and option == "show_all" and (value == "on" or value == "off") then
			app.find_files.show_all_files = value == "on"
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
	open_picker("find_files", function(app)
		app.find_files:show(false, app.windows_service)
	end)
end

function M.live_grep()
	open_picker("live_grep", function(app)
		app.live_grep:show(false, app.windows_service)
	end)
end

function M.live_grep_selection()
	open_picker("live_grep", function(app)
		local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
		vim.cmd.normal({ args = { "\27" }, bang = true })
		app.live_grep:grep_text(lines[1] or "", app.windows_service)
	end)
end

function M.buffers()
	open_picker("buffers", function(app)
		app.buffers:show(false, app.windows_service)
	end)
end

function M.lsp_dynamic_workspace_symbols()
	open_picker("lsp_dynamic_workspace_symbols", function(app)
		app.workspace_symbols:show(false, app.windows_service)
	end)
end

function M.git_status()
	open_picker("git_status", function(app)
		app.git_status:show(false, app.windows_service)
	end)
end

function M.diagnostics()
	open_picker("diagnostics", function(app)
		app.diagnostics:show(false, app.windows_service)
	end)
end

function M.file_browser()
	local app = get_app_context()
	if app and is_open(app) and app.state.last_picker == "file_browser" then
		app.windows_service:close()
		vim.cmd.stopinsert()
		return
	end
	open_picker("file_browser", function(app)
		app.file_browser:open(app.windows_service)
	end)
end

function M.reveal()
	open_picker("file_browser", function(app)
		app.file_browser:reveal(app.windows_service)
	end)
end

function M.lsp_definitions()
	local app = get_app_context()
	if not app or is_open(app) then
		return
	end
	if app.lsp_locations:show_locations("textDocument/definition", app.windows_service) then
		app.state.last_picker = "lsp_locations"
	end
end

function M.lsp_references()
	local app = get_app_context()
	if not app or is_open(app) then
		return
	end
	if app.lsp_locations:show_locations("textDocument/references", app.windows_service) then
		app.state.last_picker = "lsp_locations"
	end
end

function M.resume()
	local app = get_app_context()
	if not app or is_open(app) then
		return
	end
	local picker = app.pickers[app.state.last_picker or ""]
	if picker then
		picker:resume(app.windows_service)
	end
end

return M
