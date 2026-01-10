local M = {}

local function show_tree(pattern)
	local ignore = "vendor"
	-- noreport to disable summary
	-- prune is hiding dirs that have no matched files
	local cmd = { "tree", "-P", pattern, "-I", ignore, "--noreport", "--prune" }
	local lines = vim.fn.systemlist(cmd)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	local w = math.floor(vim.o.columns * 0.8)
	local h = math.floor(vim.o.lines * 0.8)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = w,
		height = h,
		row = math.floor((vim.o.lines - h) / 2),
		col = math.floor((vim.o.columns - w) / 2),
		style = "minimal",
		border = "rounded",
	})

	-- close on focus loss
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = buf,
		once = true,
		callback = function()
			vim.schedule(function()
				if vim.api.nvim_win_is_valid(win) then
					vim.api.nvim_win_close(win, true)
				end
			end)
		end,
	})

	vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf })
	vim.keymap.set("n", "<CR>", function()
		local line = vim.api.nvim_get_current_line()
		local path = line:gsub("[│├└─ ]+", ""):match("^%s*(.-)%s*$")
		if vim.fn.filereadable(path) == 1 then
			vim.cmd("close")
			vim.cmd("edit " .. vim.fn.fnameescape(path))
		end
	end, { buffer = buf })
end

function M.setup(opts)
	opts = opts or {}
	opts = vim.tbl_extend("force", opts, {})

	--cmd = "tree -P '*Service*' -C --noreport -I 'vendor' --prune"
	local term = "*Service*"
	local ignore = "vendor"
	-- noreport to disable summary
	-- prune is hiding dirs that have no matched files
	local cmd = { "tree", "-P", term, "-I", ignore, "--noreport", "--prune" }
	vim.keymap.set("n", "<space>k", function()
		local search = vim.fn.input("Search: ")
		show_tree(search ~= "" and search or nil)
	end)
end

return M
