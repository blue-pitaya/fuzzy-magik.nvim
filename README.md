# fuzzy-magik.nvim

Minimal Neovim plugin for fuzzy search.

## Usage

The plugin sets no keybindings. Map the finder yourself:

```lua
vim.keymap.set("n", "<Space><Space>", function()
	require("fuzzy-magik").find_files()
end)
vim.keymap.set("n", "<Space>g", function()
	require("fuzzy-magik").live_grep()
end)
vim.keymap.set("x", "<Space>g", function()
	require("fuzzy-magik").live_grep_selection()
end)
vim.keymap.set("n", "<Space>r", function()
	require("fuzzy-magik").resume()
end)
vim.keymap.set("n", "<Space>j", function()
	require("fuzzy-magik").buffers()
end)
vim.keymap.set("n", "<Space>n", function()
	require("fuzzy-magik").lsp_dynamic_workspace_symbols()
end)
vim.keymap.set("n", "<Space>s", function()
	require("fuzzy-magik").git_status()
end)
vim.keymap.set("n", "<Space>d", function()
	require("fuzzy-magik").diagnostics()
end)
vim.keymap.set("n", "<C-n>", function()
	require("fuzzy-magik").file_browser()
end)
vim.keymap.set("n", "<Space>e", function()
	require("fuzzy-magik").reveal()
end)
vim.keymap.set("n", "gd", function()
	require("fuzzy-magik").lsp_definitions()
end)
vim.keymap.set("n", "gr", function()
	require("fuzzy-magik").lsp_references()
end)
```

## Commands

- `:FuzzyMagik find_files show_all on|off` toggles showing `.gitignore`d and hidden files in find files.

## Requirements

- Neovim >= 0.10.0
