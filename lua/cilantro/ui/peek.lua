local config = require("cilantro.config")

local M = {}

M.win = nil
M.buf = nil
M.list_win = nil
M.focused = false

local function win_is_valid(win)
  return win and vim.api.nvim_win_is_valid(win)
end

-- A peek/focus window is split off a scroll-bound window and inherits its
-- scrollbind/cursorbind. Clear them so editing a task file does not scroll
-- the calendar and list panels.
local function clear_scroll_bind(win)
  if win_is_valid(win) then
    pcall(vim.api.nvim_set_option_value, "scrollbind", false, { win = win })
    pcall(vim.api.nvim_set_option_value, "cursorbind", false, { win = win })
  end
end

function M.open(task, opts)
  opts = opts or {}
  local cfg = config.get()
  local list = require("cilantro.ui.list")

  if opts.focus then
    -- Go straight to focus mode
    local list_win = list.get_win()
    if list_win then
      M.list_win = list_win
    end

    if win_is_valid(M.win) then
      vim.api.nvim_set_current_win(M.win)
      vim.cmd("edit " .. vim.fn.fnameescape(task.path))
    else
      if win_is_valid(M.list_win) then
        vim.api.nvim_set_current_win(M.list_win)
      end
      vim.cmd("edit " .. vim.fn.fnameescape(task.path))
      M.win = vim.api.nvim_get_current_win()
    end

    -- Close list window if it's separate from peek
    if win_is_valid(M.list_win) and M.list_win ~= M.win then
      vim.api.nvim_win_close(M.list_win, false)
    end

    M.buf = vim.api.nvim_get_current_buf()
    M.focused = true
    clear_scroll_bind(M.win)
    M.setup_peek_keymaps()
    return
  end

  -- Normal peek mode: open in bottom split
  local list_win = list.get_win()
  if list_win then
    M.list_win = list_win
  end

  if win_is_valid(M.win) then
    vim.api.nvim_set_current_win(M.win)
    vim.cmd("edit " .. vim.fn.fnameescape(task.path))
  else
    vim.cmd("botright split " .. vim.fn.fnameescape(task.path))
    M.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_height(M.win, cfg.peek_height)
  end

  M.buf = vim.api.nvim_get_current_buf()
  M.focused = false
  clear_scroll_bind(M.win)
  M.setup_peek_keymaps()
end

function M.close()
  if win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, false)
  end
  M.win = nil
  M.buf = nil
  M.focused = false
end

function M.focus()
  if not win_is_valid(M.win) then
    return
  end

  local list = require("cilantro.ui.list")
  local list_win = list.get_win()
  if list_win then
    M.list_win = list_win
  end

  if win_is_valid(M.list_win) and M.list_win ~= M.win then
    vim.api.nvim_win_close(M.list_win, false)
  end

  M.focused = true
end

function M.unfocus()
  if not win_is_valid(M.win) then
    return
  end

  local list = require("cilantro.ui.list")

  local peek_win = M.win

  -- Create a new split above for the list
  vim.api.nvim_set_current_win(peek_win)
  vim.cmd("aboveleft split")
  local new_list_win = vim.api.nvim_get_current_win()

  -- Put the list buffer in the new window
  local list_buf = list.get_buf()
  vim.api.nvim_win_set_buf(new_list_win, list_buf)

  -- Resize peek back to configured height
  local cfg = config.get()
  vim.api.nvim_win_set_height(peek_win, cfg.peek_height)

  -- Update state
  M.list_win = new_list_win
  M.focused = false

  -- Re-render list and focus list window
  list.render()
  vim.api.nvim_set_current_win(new_list_win)
end

function M.toggle_focus()
  if M.focused then
    M.unfocus()
  else
    M.focus()
  end
end

function M.is_open()
  return win_is_valid(M.win)
end

function M.setup_peek_keymaps()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    return
  end

  local cfg = config.get()
  local key = cfg.keymaps.focus
  if key and key ~= false then
    vim.keymap.set("n", key, function()
      M.toggle_focus()
    end, { buffer = M.buf, nowait = true, desc = "Toggle focus mode" })
  end
end

return M
