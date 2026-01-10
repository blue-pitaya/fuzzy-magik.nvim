local M = {}

---@class AppContext
---@field prompt_win integer
---@field prompt_buf integer
---@field results_win integer
---@field results_buf integer
---@field current_results ListItem[]
---@field has_devicons boolean
---@field devicons unknown

local function create_results_buffer()
	local results_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[results_buf].buftype = "nofile"
	vim.bo[results_buf].bufhidden = "wipe"
	vim.bo[results_buf].modifiable = false

	return results_buf
end

local function create_propmt_buffer()
	local prompt_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[prompt_buf].buftype = "prompt"
	vim.bo[prompt_buf].bufhidden = "wipe"
	vim.fn.prompt_setprompt(prompt_buf, "> ")

	return prompt_buf
end

---@param ctx AppContext
---@param pattern string
local function update_results(ctx, pattern)
	vim.bo[ctx.results_buf].modifiable = true

	ctx.current_results, highlights = require("tree-from-rg").create_tree_output(ctx, pattern)
	local lines = {}
	for _, item in ipairs(ctx.current_results) do
		table.insert(lines, item.line)
	end

	vim.api.nvim_buf_set_lines(ctx.results_buf, 0, -1, false, lines)

	local ns_id = vim.api.nvim_create_namespace("tree_highlights")
	for _, hl in ipairs(highlights) do
		vim.api.nvim_buf_set_extmark(ctx.results_buf, ns_id, hl.line, hl.col_start, {
			end_col = hl.col_end,
			hl_group = hl.hl_group,
		})
	end

	vim.bo[ctx.results_buf].modifiable = false
end

local function close_ui(ctx)
	if vim.api.nvim_win_is_valid(ctx.prompt_win) then
		vim.api.nvim_win_close(ctx.prompt_win, true)
	end
	if vim.api.nvim_win_is_valid(ctx.results_win) then
		vim.api.nvim_win_close(ctx.results_win, true)
	end
end

---@param ctx AppContext
local function show_tree_ui(ctx)
	ctx.prompt_buf = create_propmt_buffer()
	ctx.results_buf = create_results_buffer()

	local w = math.floor(vim.o.columns * 0.9)
	local col = math.floor((vim.o.columns - w) / 2)

	ctx.prompt_win = vim.api.nvim_open_win(ctx.prompt_buf, true, {
		relative = "editor",
		width = w,
		height = 1,
		row = 1,
		col = col,
		style = "minimal",
		border = "rounded",
	})

	ctx.results_win = vim.api.nvim_open_win(ctx.results_buf, false, {
		relative = "editor",
		width = w,
		height = vim.o.lines - 9,
		row = 4,
		col = col,
		style = "minimal",
		border = "rounded",
	})
	vim.wo[ctx.results_win].cursorline = true

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = ctx.prompt_buf,
		callback = function()
			local text = vim.api.nvim_buf_get_lines(ctx.prompt_buf, 0, 1, false)[1]
			text = text:gsub("^> ", "")
			update_results(ctx, text)
		end,
	})

	vim.keymap.set("n", "<Esc>", function()
		vim.api.nvim_set_current_win(ctx.results_win)
	end, { buffer = ctx.prompt_buf })
	vim.keymap.set("i", "<Esc>", function()
		vim.api.nvim_set_current_win(ctx.results_win)
	end, { buffer = ctx.prompt_buf })

	vim.keymap.set("n", "<Esc>", function()
		close_ui(ctx)
	end, { buffer = ctx.results_buf })

	vim.keymap.set("n", "<CR>", function()
		local line_num = vim.api.nvim_win_get_cursor(0)[1]
		local item = ctx.current_results[line_num]
		close_ui(ctx)
		vim.cmd.edit(item.path)
	end, { buffer = ctx.results_buf })

	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(ctx.prompt_win),
		callback = function()
			close_ui(ctx)
		end,
		once = true,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(ctx.results_win),
		callback = function()
			close_ui(ctx)
		end,
		once = true,
	})

	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = ctx.prompt_buf,
		callback = function()
			vim.schedule(function()
				if
					vim.api.nvim_get_current_win() ~= ctx.prompt_win
					and vim.api.nvim_get_current_win() ~= ctx.results_win
				then
					close_ui(ctx)
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = ctx.results_buf,
		callback = function()
			vim.schedule(function()
				if
					vim.api.nvim_get_current_win() ~= ctx.prompt_win
					and vim.api.nvim_get_current_win() ~= ctx.results_win
				then
					close_ui(ctx)
				end
			end)
		end,
	})

	vim.cmd.startinsert()
end

function M.setup(opts)
	opts = opts or {}

	vim.api.nvim_set_hl(0, "TreePrefix", { fg = "#6c6c6c", bold = true }) -- Blue for directories
	vim.api.nvim_set_hl(0, "TreeDirectory", { fg = "#0d73e8", bold = true }) -- Blue for directories
	vim.api.nvim_set_hl(0, "TreeFile", { link = "Normal" }) -- Normal color for files

	local has_devicons, devicons = pcall(require, "nvim-web-devicons")

	---@type AppContext
	local ctx = {
		prompt_win = 0,
		prompt_buf = 0,
		results_win = 0,
		results_buf = 0,
		current_results = {},
		has_devicons = has_devicons,
		devicons = devicons,
	}

	vim.keymap.set("n", "<space>k", function()
		show_tree_ui(ctx)
	end)
end

return M
