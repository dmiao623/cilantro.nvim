# cilantro.nvim

A file-based task manager for Neovim.

Tasks and events are stored as individual Markdown files with YAML frontmatter. The plugin provides a queryable task list with an optional calendar column, while files remain ordinary editable buffers.

## Features

- File-based task and event storage
- Markdown files with YAML frontmatter
- Three-panel layout: file tree, events, and tasks
- Queryable task list UI
- Calendar column with synchronized scrolling
- Simple task creation, deletion, and status updates
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