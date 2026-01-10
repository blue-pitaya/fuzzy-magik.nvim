local M = {}

local function create_results_buffer()
	local results_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[results_buf].buftype = "nofile"
	vim.bo[results_buf].bufhidden = "wipe"

	return results_buf
end

local function create_propmt_buffer()
	local prompt_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[prompt_buf].buftype = "prompt"
	vim.bo[prompt_buf].bufhidden = "wipe"
	vim.fn.prompt_setprompt(prompt_buf, "> ")

	return prompt_buf
end

local function update_results(ctx, pattern)
	if pattern == "" then
		vim.api.nvim_buf_set_lines(ctx.results_buf, 0, -1, false, { "" })
		return
	end

	local ignore = "vendor"
	local cmd = { "tree", "-P", pattern, "-I", ignore, "--noreport", "--prune" }
	local lines = vim.fn.systemlist(cmd)
	vim.api.nvim_buf_set_lines(ctx.results_buf, 0, -1, false, lines)
end

local function close_ui(ctx)
	if vim.api.nvim_win_is_valid(ctx.prompt_win) then
		vim.api.nvim_win_close(ctx.prompt_win, true)
	end
	if vim.api.nvim_win_is_valid(ctx.results_win) then
		vim.api.nvim_win_close(ctx.results_win, true)
	end
end

local function show_tree_ui()
	local ctx = {}

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
	vim.keymap.set("n", "<space>k", show_tree_ui)
end

return M
