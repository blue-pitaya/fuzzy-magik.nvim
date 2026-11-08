local M = {}

M.WINHIGHLIGHT = {
	default = "Normal:FuzzyMagikNormal,NormalFloat:FuzzyMagikNormal,FloatBorder:FuzzyMagikBorder",
	active = "Normal:FuzzyMagikNormal,NormalFloat:FuzzyMagikNormal,FloatBorder:FuzzyMagikBorderActive",
}

M.PROMPT = "> "

M.WIDTH_RATIO = 0.9
M.RESULTS_WIDTH_RATIO = 0.4
M.HEIGHT_MARGIN = 9
M.START_ROW = 4

M.highlights = {}

---@param text string
function M.message(text)
	return { { line = text, path = "" } }
end

---@param text string
---@param pattern string
function M.fuzzy_match_cols(text, pattern)
	local cols = {}
	local search_from = 1
	local lower_text = text:lower()
	for char in pattern:lower():gmatch(".") do
		local col = lower_text:find(char, search_from, true)
		if not col then
			return nil
		end
		table.insert(cols, col)
		search_from = col + 1
	end
	return cols
end

---@param line integer
---@param offset integer
---@param cols integer[]
function M.add_match_highlights(line, offset, cols)
	for _, col in ipairs(cols) do
		table.insert(M.highlights, {
			line = line,
			col_start = offset + col - 1,
			col_end = offset + col,
			hl_group = "FuzzyMagikMatch",
		})
	end
end

---@param line integer
---@param offset integer
---@param filepath string
function M.add_path_highlights(line, offset, filepath)
	local name_col = filepath:match("()[^/]*$")
	if name_col > 1 then
		table.insert(M.highlights, {
			line = line,
			col_start = offset,
			col_end = offset + name_col - 1,
			hl_group = "FuzzyMagikPath",
		})
	end

	local ext_col = filepath:match("[^/]()%.[^./]+$")
	if ext_col then
		table.insert(M.highlights, {
			line = line,
			col_start = offset + ext_col - 1,
			col_end = offset + #filepath,
			hl_group = "FuzzyMagikExtension",
		})
	end
end

---@param buf_options table
---@param enter boolean
---@param config table
function M.open_float(buf_options, enter, config)
	local buf = vim.api.nvim_create_buf(false, true)
	for option, value in pairs(buf_options) do
		vim.bo[buf][option] = value
	end
	config.relative = "editor"
	config.border = "rounded"
	return buf, vim.api.nvim_open_win(buf, enter, config)
end

return M
