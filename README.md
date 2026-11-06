# nvim-file-tree-fuzzy-finder

Minimal Neovim plugin for fuzzy file search using the `tree` command.

## Installation

### lazy.nvim

```lua
return {
	{
		dir = "/path/to/this/repo",
		config = function()
			require("fuzzy-magik").setup({})
		end,
	},
}
```

## Usage

Press `<Space>k` to search.

## Requirements

- Neovim >= 0.10.0
