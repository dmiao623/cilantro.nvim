# cilantro.nvim

A file-based task manager for Neovim.

Tasks are stored as individual Markdown files with YAML frontmatter. The plugin provides a queryable task list, while task files remain ordinary editable buffers.

## Features

- File-based task storage
- Markdown task files with YAML frontmatter
- Queryable task list UI
- Simple task creation and status updates
- Sort and filter support
- Customizable keymaps

## Installation

Using `lazy.nvim`:

```lua
{
  "dmiao623/cilantro.nvim",
  config = function()
    require("cilantro").setup({
      task_dir = "~/tasks",
    })
  end,
}