local utils = require("fuzzy-magik.utils")

---@class GitStatus : Picker
---@field items FuzzyMagikItem[]
---@field last_line integer
---@field windows_service WindowsService?
local GitStatus = {}
GitStatus.__index = GitStatus

---@return GitStatus
function GitStatus.new()
	return setmetatable({
		items = {},
		last_line = -1,
	}, GitStatus)
end

---@param pattern string
function GitStatus:create_output(pattern)
	local root = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
	if root.code ~= 0 then
		return utils.message("Not a git repository")
	end
	local root_dir = vim.trim(root.stdout or "")

	local result = vim.system({ "git", "status", "--porcelain=v1", "-z", "--untracked-files=all" }, { text = true })
		:wait()
	if result.code ~= 0 then
		return utils.message("git status failed")
	end

	local entries = vim.split(result.stdout or "", "\0", { plain = true, trimempty = true })
	---@type FuzzyMagikItem[]
	local items = {}
	local i = 1
	while i <= #entries do
		local entry = entries[i]
		local status = entry:sub(1, 2)
		local filepath = vim.fn.fnamemodify(root_dir .. "/" .. entry:sub(4), ":.")
		if status:find("[RC]") then
			i = i + 1
		end
		i = i + 1

		local cols = utils.fuzzy_match_cols(filepath, pattern)
		if cols then
			local line = #items
			local prefix = status .. " "
			if status == "??" then
				table.insert(utils.highlights, {
					line = line,
					col_start = 0,
					col_end = 2,
					hl_group = "FuzzyMagikGitUntracked",
				})
			else
				if status:sub(1, 1) ~= " " then
					table.insert(utils.highlights, {
						line = line,
						col_start = 0,
						col_end = 1,
						hl_group = "FuzzyMagikGitStaged",
					})
				end
				if status:sub(2, 2) ~= " " then
					table.insert(utils.highlights, {
						line = line,
						col_start = 1,
						col_end = 2,
						hl_group = "FuzzyMagikGitUnstaged",
					})
				end
			end
			utils.add_path_highlights(line, #prefix, filepath)
			utils.add_match_highlights(line, #prefix, cols)
			table.insert(items, {
				line = prefix .. filepath,
				path = filepath,
			})
		end
	end

	if #items == 0 then
		return utils.message("No changed files matching pattern: " .. pattern)
	end
	return items
end

---@param do_resume boolean
---@param windows_service WindowsService
function GitStatus:show(do_resume, windows_service)
	local resume_line = self.last_line
	self.last_line = -1
	self.items = {}

	self.windows_service = windows_service
	windows_service:open()
	self:set_autocmds()
	self:set_keymaps()
	windows_service:set_autocmds()
	windows_service:set_keymaps()

	local prompt = windows_service.prompt
	local results = windows_service.results
	local line = 1
	if do_resume then
		prompt:write_text()
		self:update_results(prompt.text)
		line = math.max(1, math.min(resume_line, #self.items))
	else
		prompt.text = ""
		self:update_results("")
	end
	vim.api.nvim_set_current_win(results.win)
	vim.api.nvim_win_set_cursor(results.win, { line, 0 })
	self.last_line = line
	self:update_preview(self.items[line])
end

---@param windows_service WindowsService
function GitStatus:resume(windows_service)
	self:show(true, windows_service)
end

function GitStatus:set_autocmds()
	local prompt = self.windows_service.prompt
	local results = self.windows_service.results

	local function on_results_cursor()
		local line = vim.api.nvim_win_get_cursor(0)[1]
		if line ~= self.last_line then
			self.last_line = line
			self:update_preview(self.items[line])
		end
	end

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = prompt.buf,
		callback = function()
			self:update_results(prompt:read_text())
		end,
	})

	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = results.buf,
		callback = on_results_cursor,
	})

	vim.api.nvim_create_autocmd("WinEnter", {
		buffer = results.buf,
		callback = on_results_cursor,
	})
end

function GitStatus:set_keymaps()
	local prompt = self.windows_service.prompt
	local results = self.windows_service.results

	local function send_to_quickfix()
		self:send_to_quickfix()
	end

	vim.keymap.set({ "n", "i" }, "<C-q>", send_to_quickfix, { buffer = prompt.buf })

	vim.keymap.set("n", "<C-q>", send_to_quickfix, { buffer = results.buf })
	vim.keymap.set("n", "<CR>", function()
		local item = self.items[vim.api.nvim_win_get_cursor(0)[1]]
		if not item or item.path == "" then
			return
		end
		self.windows_service:close()
		vim.cmd.edit(item.path)
	end, { buffer = results.buf })
end

---@param pattern string
function GitStatus:update_results(pattern)
	utils.highlights = {}
	self.items = self:create_output(pattern)
	self.last_line = -1
	self.windows_service.results:render(self.items, utils.highlights)
end

---@param item FuzzyMagikItem
---@return boolean
function GitStatus:is_current(item)
	return self.items[self.last_line] == item
end

---@param item FuzzyMagikItem
---@param lines string[]
function GitStatus:set_preview_lines(item, lines)
	if self:is_current(item) then
		self.windows_service.preview:set_lines(lines)
	end
end

---@param item FuzzyMagikItem?
function GitStatus:update_preview(item)
	if not item then
		return
	end

	if vim.fn.filereadable(item.path) == 0 then
		self:set_preview_lines(item, { "File not found: " .. item.path })
		return
	end

	local function show_read_error()
		vim.schedule(function()
			self:set_preview_lines(item, { "Error reading file" })
		end)
	end

	vim.uv.fs_open(item.path, "r", 438, function(open_err, fd)
		if open_err or not fd then
			show_read_error()
			return
		end
		vim.uv.fs_fstat(fd, function(stat_err, stat)
			if stat_err or not stat then
				vim.uv.fs_close(fd)
				show_read_error()
				return
			end
			vim.uv.fs_read(fd, stat.size, 0, function(read_err, data)
				vim.uv.fs_close(fd)
				if read_err or not data then
					show_read_error()
					return
				end
				vim.schedule(function()
					if not self:is_current(item) then
						return
					end
					local lines = vim.split(data, "\n")
					if lines[#lines] == "" then
						table.remove(lines)
					end
					self.windows_service.preview:show_file(item.path, lines)
				end)
			end)
		end)
	end)
end

function GitStatus:send_to_quickfix()
	local entries = {}
	for _, item in ipairs(self.items) do
		if item.path ~= "" then
			table.insert(entries, { filename = item.path, lnum = 1 })
		end
	end
	self.windows_service:close()
	vim.cmd.stopinsert()
	vim.fn.setqflist(entries, "r")
	vim.cmd.copen()
end

return GitStatus
