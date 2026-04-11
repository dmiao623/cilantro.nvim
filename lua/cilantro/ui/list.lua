local config = require("cilantro.config")
local index = require("cilantro.index")

local M = {}

M.bufnr = nil
M.task_ids = {}
M.subtask_idx = {}
M.query_opts = {}
M.hide_done = false
M.show_paths = true

local ns = vim.api.nvim_create_namespace("CilantroList")

local STATUS_ICONS = {
  todo = "[ ]",
  in_progress = "[>]",
  done = "[x]",
  cancelled = "[-]",
}

local STATUS_HL = {
  todo = "CilantroStatusTodo",
  in_progress = "CilantroStatusInProgress",
  done = "CilantroStatusDone",
  cancelled = "CilantroStatusCancelled",
}

local function pad_right(str, width)
  if #str >= width then
    return str:sub(1, width)
  end
  return str .. string.rep(" ", width - #str)
end

function M.get_buf()
  if M.bufnr and vim.api.nvim_buf_is_valid(M.bufnr) then
    return M.bufnr
  end

  M.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = M.bufnr })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = M.bufnr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = M.bufnr })
  vim.api.nvim_set_option_value("filetype", "cilantro", { buf = M.bufnr })
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.bufnr })

  M.setup_keymaps(M.bufnr)

  return M.bufnr
end

local function task_display_name(t)
  if not M.show_paths or not t.path then
    return t.title or "(untitled)"
  end

  local cfg = config.get()
  local rel = t.path:gsub("^" .. vim.pesc(cfg.task_dir) .. "/", "")
  -- Strip the filename, keep only directory parts
  local dir = vim.fn.fnamemodify(rel, ":h")
  local title = t.title or "(untitled)"

  if dir == "." then
    return title
  end

  return dir:gsub("/", " / ") .. " / " .. title
end

local function render_task_line(t)
  local icon = STATUS_ICONS[t.status] or "[?]"
  local name = task_display_name(t)
  local date = t.end_date or ""
  local minutes = t.estimated_minutes and (t.estimated_minutes .. "m") or "-"

  local title_col = pad_right(name, 50)
  local date_col = pad_right(date, 12)
  local min_col = pad_right(minutes, 6)

  return "  " .. icon .. " " .. title_col .. " " .. date_col .. " " .. min_col
end

local function task_line_highlights(t, line_idx)
  local icon = STATUS_ICONS[t.status] or "[?]"
  local title_col_width = 50
  local date_col_width = 12

  local status_hl = STATUS_HL[t.status] or "CilantroStatusTodo"
  local title_hl = t.status == "done" and "CilantroTitleDone" or "CilantroTitle"
  local date_hl = t.status == "done" and "CilantroTitleDone" or "CilantroDate"
  local min_hl = t.status == "done" and "CilantroTitleDone" or "CilantroMinutes"

  local icon_start = 2
  local icon_end = icon_start + #icon
  local title_start = icon_end + 1
  local title_end = title_start + title_col_width
  local date_start = title_end + 1
  local date_end = date_start + date_col_width
  local min_start = date_end + 1

  local hls = {
    { line_idx, status_hl, icon_start, icon_end },
    { line_idx, title_hl, title_start, title_end },
    { line_idx, date_hl, date_start, date_end },
    { line_idx, min_hl, min_start, -1 },
  }

  return hls
end

local function render_subtask_line(subtask)
  local icon = STATUS_ICONS[subtask.status] or "[?]"
  return "      " .. icon .. " " .. (subtask.name or "(unnamed)")
end

local function subtask_line_highlights(subtask, line_idx)
  local icon = STATUS_ICONS[subtask.status] or "[?]"
  local status_hl = STATUS_HL[subtask.status] or "CilantroStatusTodo"
  local title_hl = subtask.status == "done" and "CilantroTitleDone" or "CilantroTitle"

  local icon_start = 6
  local icon_end = icon_start + #icon
  local title_start = icon_end + 1

  return {
    { line_idx, status_hl, icon_start, icon_end },
    { line_idx, title_hl, title_start, -1 },
  }
end

function M.render()
  local buf = M.get_buf()

  -- Apply hide_done filter
  local query = vim.tbl_extend("force", {}, M.query_opts)
  if M.hide_done then
    if not query.status then
      local cfg = config.get()
      local visible = {}
      for _, s in ipairs(cfg.status_order) do
        if s ~= "done" then
          table.insert(visible, s)
        end
      end
      query.status = visible
    end
  end

  local tasks = index.query(query)

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  M.task_ids = {}
  M.subtask_idx = {}

  if #tasks == 0 then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "  No tasks found. Press 'a' to create one." })
    vim.api.nvim_buf_add_highlight(buf, ns, "CilantroEmpty", 0, 0, -1)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    return
  end

  local lines = {}
  local highlights = {}
  local sort_by = query.sort_by or "end_date"
  local show_headers = sort_by == "end_date"
  local line_idx = 0

  local function append_task(t)
    table.insert(lines, render_task_line(t))
    table.insert(M.task_ids, t.id)
    for _, hl in ipairs(task_line_highlights(t, line_idx)) do
      table.insert(highlights, hl)
    end
    line_idx = line_idx + 1

    for si, subtask in ipairs(t.subtasks) do
      table.insert(lines, render_subtask_line(subtask))
      table.insert(M.task_ids, t.id)
      M.subtask_idx[#M.task_ids] = si
      for _, hl in ipairs(subtask_line_highlights(subtask, line_idx)) do
        table.insert(highlights, hl)
      end
      line_idx = line_idx + 1
    end
  end

  if show_headers then
    local current_date = nil
    for _, t in ipairs(tasks) do
      local task_date = t.end_date or "No end date"
      if task_date ~= current_date then
        current_date = task_date
        local header = "── " .. current_date .. " ──"
        table.insert(lines, header)
        table.insert(M.task_ids, false)
        table.insert(highlights, { line_idx, "CilantroHeader", 0, -1 })
        line_idx = line_idx + 1
      end
      append_task(t)
    end
  else
    for _, t in ipairs(tasks) do
      append_task(t)
    end
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buf, ns, hl[2], hl[1], hl[3], hl[4])
  end

  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
end

function M.open(opts)
  opts = opts or {}
  local buf = M.get_buf()
  local win = opts.win or vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  M.render()
end

function M.get_cursor_task()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local tid = M.task_ids[row]
  if not tid then
    return nil
  end
  return index.tasks[tid]
end

function M.is_visible()
  if not M.bufnr or not vim.api.nvim_buf_is_valid(M.bufnr) then
    return false
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == M.bufnr then
      return true
    end
  end
  return false
end

function M.get_win()
  if not M.bufnr then
    return nil
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == M.bufnr then
      return win
    end
  end
  return nil
end

function M.cycle_status(direction)
  direction = direction or 1
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local tid = M.task_ids[row]
  if not tid then
    return
  end

  local t = index.tasks[tid]
  if not t then
    return
  end

  local cfg = config.get()
  local order = cfg.status_order
  local sub_idx = M.subtask_idx[row]

  local current_status
  if sub_idx then
    local subtask = t.subtasks[sub_idx]
    if not subtask then
      return
    end
    current_status = subtask.status
  else
    current_status = t.status
  end

  local current_idx = nil
  for i, s in ipairs(order) do
    if s == current_status then
      current_idx = i
      break
    end
  end
  if not current_idx then
    current_idx = 1
  end

  local next_idx = ((current_idx - 1 + direction) % #order) + 1
  local new_status = order[next_idx]

  local task_mod = require("cilantro.task")
  local changes
  if sub_idx then
    local new_subtasks = vim.deepcopy(t.subtasks)
    new_subtasks[sub_idx].status = new_status
    changes = { subtasks = new_subtasks }
  else
    changes = { status = new_status }
  end

  local updated = task_mod.update(t, changes)
  if updated then
    index.put(updated)
    M.render()
  end
end

function M.set_filter()
  local cfg = config.get()
  local choices = { "all" }
  for _, s in ipairs(cfg.status_order) do
    table.insert(choices, s)
  end

  vim.ui.select(choices, { prompt = "Filter by status:" }, function(choice)
    if not choice then
      return
    end
    if choice == "all" then
      M.query_opts.status = nil
    else
      M.query_opts.status = choice
    end
    M.render()
  end)
end

function M.set_sort()
  local fields = { "end_date", "created_at", "updated_at", "title", "status", "estimated_minutes", "start_date" }
  vim.ui.select(fields, { prompt = "Sort by:" }, function(choice)
    if not choice then
      return
    end
    M.query_opts.sort_by = choice
    M.render()
  end)
end

function M.toggle_sort_direction()
  M.query_opts.sort_desc = not M.query_opts.sort_desc
  M.render()
end

function M.sort_by_end_date()
  M.query_opts.sort_by = "end_date"
  M.render()
end

function M.sort_by_minutes()
  M.query_opts.sort_by = "estimated_minutes"
  M.render()
end

function M.sort_by_alpha()
  M.query_opts.sort_by = "title"
  M.render()
end

function M.toggle_done()
  M.hide_done = not M.hide_done
  M.render()
end

function M.toggle_paths()
  M.show_paths = not M.show_paths
  M.render()
end

function M.setup_keymaps(bufnr)
  local cfg = config.get()
  local km = cfg.keymaps

  local function map(key, fn, desc)
    if key and key ~= false then
      vim.keymap.set("n", key, fn, { buffer = bufnr, nowait = true, desc = desc })
    end
  end

  map(km.open, function()
    local t = M.get_cursor_task()
    if t then
      require("cilantro.ui.peek").open(t)
    end
  end, "Open task in peek split")

  map(km.cycle_status, function()
    M.cycle_status(1)
  end, "Cycle status forward")

  map(km.cycle_status_back, function()
    M.cycle_status(-1)
  end, "Cycle status backward")

  map(km.create, function()
    require("cilantro").create_task()
  end, "Create new task")

  map(km.filter, function()
    M.set_filter()
  end, "Set filter")

  map(km.sort, function()
    M.set_sort()
  end, "Set sort field")

  map(km.sort_direction, function()
    M.toggle_sort_direction()
  end, "Toggle sort direction")

  map(km.sort_end_date, function()
    M.sort_by_end_date()
  end, "Sort by end date")

  map(km.sort_minutes, function()
    M.sort_by_minutes()
  end, "Sort by estimated minutes")

  map(km.sort_alpha, function()
    M.sort_by_alpha()
  end, "Sort alphabetically")

  map(km.toggle_done, function()
    M.toggle_done()
  end, "Toggle showing completed tasks")

  map(km.toggle_paths, function()
    M.toggle_paths()
  end, "Toggle showing file paths")

  map(km.refresh, function()
    require("cilantro").refresh()
  end, "Refresh")

  map(km.focus, function()
    local t = M.get_cursor_task()
    if t then
      require("cilantro.ui.peek").open(t, { focus = true })
    end
  end, "Open task in focus mode")

  map(km.close, function()
    require("cilantro").close()
  end, "Close cilantro")
end

return M
