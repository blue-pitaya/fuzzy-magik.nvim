# fuzzy-magik.nvim

Minimal Neovim plugin for fuzzy search.

## Usage

The plugin sets no keybindings. Map the finder yourself:

```lua
vim.keymap.set("n", "<Space><Space>", function()
	require("fuzzy-magik").find_files()
end)
```

## Requirements

- Neovim >= 0.10.0
