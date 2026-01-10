local M = {}

---@param ctx AppContext
---@param name string
---@param is_directory boolean
---@return string icon
---@return string|nil hl_group
local function get_icon(ctx, name, is_directory)
	if is_directory then
		return "", "TreeDirectory"
	end

	if ctx.has_devicons then
		local icon, hl = ctx.devicons.get_icon(name, nil, { default = true })
		return icon .. " ", hl
	end

	return " ", nil
end

---@class TreeNode
---@field _is_file boolean
---@field _path string
---@field [string] TreeNode

---@class TreeEntry
---@field name string
---@field data TreeNode

---@class ListItem
---@field line string
---@field path string

local TREE_CHARS = {
	vertical = "│ ",
	branch = "├─",
	last = "└─",
	space = "  ",
}

---@param files string[]
---@return TreeNode
local function build_tree(files)
	---@type TreeNode
	local tree = {
		_is_file = false,
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

---@param ctx AppContext
---@param node TreeNode
---@param prefix string
---@param items ListItem[]
---@param highlights table[]
local function generate_tree_lines(ctx, node, prefix, items, highlights)
	local entries = sort_entries(node)
	for i, entry in ipairs(entries) do
		local name = entry.name
		local data = entry.data
		local is_last_entry = (i == #entries)
		local icon, icon_hl = get_icon(ctx, name, not data._is_file)
		local connector = is_last_entry and TREE_CHARS.last or TREE_CHARS.branch

		-- Build line with icon inserted
		local line = prefix .. connector .. icon .. name

		local line_num = #items
		local prefix_len = #prefix
		local connector_len = #connector
		local icon_start = prefix_len + connector_len
		local icon_len = vim.fn.strwidth(icon)
		local name_start = icon_start + icon_len

		-- Highlight prefix (tree structure before connector)
		if prefix_len > 0 then
			table.insert(highlights, {
				line = line_num,
				col_start = 0,
				col_end = prefix_len,
				hl_group = "TreePrefix",
			})
		end

		-- Highlight connector
		table.insert(highlights, {
			line = line_num,
			col_start = prefix_len,
			col_end = icon_start,
			hl_group = "TreePrefix",
		})

		-- Highlight icon
		if icon_hl then
			table.insert(highlights, {
				line = line_num,
				col_start = icon_start,
				col_end = name_start,
				hl_group = icon_hl,
			})
		end

		-- Highlight name (file or directory)
		if data._is_file then
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

		table.insert(items, {
			line = line,
			path = data._path,
		})

		if not data._is_file then
			local new_prefix = prefix .. (is_last_entry and TREE_CHARS.space or TREE_CHARS.vertical)
			generate_tree_lines(ctx, data, new_prefix, items, highlights)
		end
	end
end

---@param ctx AppContext
---@param pattern string
---@return ListItem[]
---@return table[]
function M.create_tree_output(ctx, pattern)
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
	local items = {
		{
			line = cwd,
			path = cwd,
		},
	}
	local highlights = {
		{
			line = 0,
			col_start = 0,
			col_end = #cwd,
			hl_group = "TreeDirectory",
		},
	}
	generate_tree_lines(ctx, tree, "", items, highlights)

	return items, highlights
end

return M
