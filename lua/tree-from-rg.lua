local M = {}

---@class TreeNode
---@field _is_file boolean
---@field _path string
---@field [string] TreeNode

---@class TreeEntry
---@field name string
---@field data TreeNode

local TREE_CHARS = {
	vertical = "│   ",
	branch = "├── ",
	last = "└── ",
	space = "    ",
}

---@param files string[]
---@return TreeNode
local function build_tree(files)
	---@type TreeNode
	local tree = {
		_is_file = true,
		_path = "",
	}

	for _, filepath in ipairs(files) do
		if filepath ~= "" then
			local parts = vim.split(filepath, "/", { plain = true })
			local current = tree

			for i, part in ipairs(parts) do
				if not current[part] then
					current[part] = {
						_is_file = (i == #parts),
						_path = table.concat(vim.list_slice(parts, 1, i), "/"),
					}
				end
				---@diagnostic disable-next-line: cast-local-type
				current = current[part]
			end
		end
	end

	return tree
end

---@param entries TreeNode
---@return TreeEntry[]
local function sort_entries(entries)
	local sorted = {}

	for name, data in pairs(entries) do
		if name ~= "_is_file" and name ~= "_path" then
			table.insert(sorted, { name = name, data = data })
		end
	end

	table.sort(sorted, function(a, b)
		local a_is_file = a.data._is_file
		local b_is_file = b.data._is_file

		if a_is_file ~= b_is_file then
			return not a_is_file
		end
		return a.name < b.name
	end)

	return sorted
end

---@param node TreeNode
---@param prefix string
---@param lines string[]
---@param highlights table[]
local function generate_tree_lines(node, prefix, lines, highlights)
	local entries = sort_entries(node)

	for i, entry in ipairs(entries) do
		local name = entry.name
		local data = entry.data
		local is_last_entry = (i == #entries)

		local connector = is_last_entry and TREE_CHARS.last or TREE_CHARS.branch
		local line = prefix .. connector .. name

		local line_num = #lines
		local name_start = #prefix + #connector

		if #prefix > 0 then
			table.insert(highlights, {
				line = line_num,
				col_start = 0,
				col_end = #prefix,
				hl_group = "TreePrefix",
			})
		end

		table.insert(highlights, {
			line = line_num,
			col_start = #prefix,
			col_end = name_start,
			hl_group = "TreePrefix",
		})

		if data._is_file then
			line = line
			table.insert(highlights, {
				line = line_num,
				col_start = name_start,
				col_end = name_start + #name,
				hl_group = "TreeFile",
			})
		else
			line = line .. "/"
			table.insert(highlights, {
				line = line_num,
				col_start = name_start,
				col_end = name_start + #name + 1, -- +1 for the "/"
				hl_group = "TreeDirectory",
			})
		end

		table.insert(lines, line)

		if not data._is_file then
			local new_prefix = prefix .. (is_last_entry and TREE_CHARS.space or TREE_CHARS.vertical)
			generate_tree_lines(data, new_prefix, lines, highlights)
		end
	end
end

---@param pattern string
---@return string[]
---@return table[] Highlight information for applying colors
function M.create_tree_output(pattern)
	local escaped_pattern = vim.fn.shellescape(pattern)
	local cmd = string.format("rg --files | rg -i %s", escaped_pattern)
	local result = vim.system({ "sh", "-c", cmd }, { text = true }):wait()
	if result.code ~= 0 then
		return { "No files found matching pattern: " .. pattern }, {}
	end

	local files = vim.split(result.stdout or "", "\n", { trimempty = true })
	if #files == 0 then
		return { "No files found matching pattern: " .. pattern }, {}
	end

	local tree = build_tree(files)

	local cwd = vim.fn.getcwd()
	local lines = { cwd }
	local highlights = {
		{
			line = 0,
			col_start = 0,
			col_end = #cwd,
			hl_group = "TreeDirectory",
		},
	}
	generate_tree_lines(tree, "", lines, highlights)

	return lines, highlights
end

return M
