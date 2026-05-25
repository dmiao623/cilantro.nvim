local config = require("cilantro.config")
local index = require("cilantro.index")

local M = {}

M.bufnr = nil
M.task_ids = {}
M.subtask_idx = {}
M.query_opts = {}
M.hide_done = false
M.show_paths = nil

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

  if M.show_paths == nil then
    M.show_paths = config.get().show_paths
  end

  M.setup_keymaps(M.bufnr)

  return M.bufnr
end

local function task_display_name(t)
  if not M.show_paths or not t.path then
    return t.title or "(untitled)"
  end

  local cfg = config.get()
  local rel = t.path:gsub("^" .. vim.pesc(cfg.task_dir) .. "/", "")
  local dir = vim.fn.fnamemodify(rel, ":h")
  local title = t.title or "(untitled)"

  if dir == "." then
    return title
  end

  return dir:gsub("/", " / ") .. " / " .. title
end

function M.render_task_line(t, opts)
  opts = opts or {}
  local icon = STATUS_ICONS[t.status] or "[?]"
  local name = task_display_name(t)

  local title_col = pad_right(name, 50)

  if opts.show_date == false then
    return "  " .. icon .. " " .. title_col
  end

  local date = t.end_date or ""

  return "  " .. icon .. " " .. title_col .. " " .. date
end

function M.task_line_highlights(t, line_idx, opts)
  opts = opts or {}
  local icon = STATUS_ICONS[t.status] or "[?]"
  local title_col_width = 50

  local status_hl = STATUS_HL[t.status] or "CilantroStatusTodo"
  local title_hl = t.status == "done" and "CilantroTitleDone" or "CilantroTitle"

  local icon_start = 2
  local icon_end = icon_start + #icon
  local title_start = icon_end + 1
  local title_end = title_start + title_col_width

  local hls = {
    { line_idx, status_hl, icon_start, icon_end },
    { line_idx, title_hl, title_start, title_end },
  }

  if opts.show_date ~= false then
    local date_hl = t.status == "done" and "CilantroTitleDone" or "CilantroDate"
    local date_start = title_end + 1
    table.insert(hls, { line_idx, date_hl, date_start, -1 })
  end

  return hls
end

function M.render_subtask_line(subtask)
  local icon = STATUS_ICONS[subtask.status] or "[?]"
  return "      " .. icon .. " " .. (subtask.name or "(unnamed)")
end

function M.subtask_line_highlights(subtask, line_idx)
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

function M.get_visible_tasks()
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
  query.secondary_sort_by = M.show_paths and "path" or "title"
  return index.query(query), query
end

-- Apply pre-built lines/highlights/ids to the list buffer.
-- Used by calendar.render_pair to write into the right column.
function M.apply_render(lines, highlights, task_ids, subtask_idx)
  local buf = M.get_buf()
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for _, hl in ipairs(highlights or {}) do
    vim.api.nvim_buf_add_highlight(buf, ns, hl[2], hl[1], hl[3], hl[4])
  end
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  M.task_ids = task_ids or {}
  M.subtask_idx = subtask_idx or {}
end

-- Single-column render (no calendar). Pre-existing behaviour.
function M.render_solo()
  local buf = M.get_buf()
  local tasks, query = M.get_visible_tasks()

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
  local sort_by = query.sort_by or "end_time"
  local show_headers = sort_by == "end_time"
  local task_opts = { show_date = not show_headers }
  local line_idx = 0

  local function append_task(t)
    table.insert(lines, M.render_task_line(t, task_opts))
    table.insert(M.task_ids, t.id)
    for _, hl in ipairs(M.task_line_highlights(t, line_idx, task_opts)) do
      table.insert(highlights, hl)
    end
    line_idx = line_idx + 1

    for si, subtask in ipairs(t.subtasks) do
      table.insert(lines, M.render_subtask_line(subtask))
      table.insert(M.task_ids, t.id)
      M.subtask_idx[#M.task_ids] = si
      for _, hl in ipairs(M.subtask_line_highlights(subtask, line_idx)) do
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
        if current_date ~= nil then
          table.insert(lines, "")
          table.insert(M.task_ids, false)
          line_idx = line_idx + 1
        end
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

local function calendar_should_be_active()
  local cfg = config.get()
  if not cfg.calendar or not cfg.calendar.enabled then
    return false
  end
  local sort_by = M.query_opts.sort_by or "end_time"
  return sort_by == "end_time"
end

function M.render()
  local calendar = require("cilantro.ui.calendar")
  local active = calendar_should_be_active()

  if not active and calendar.is_visible() then
    calendar.close()
  end

  if active and calendar.is_visible() then
    calendar.render_pair()
  else
    M.render_solo()
  end
end

function M.open(opts)
  opts = opts or {}
  local buf = M.get_buf()
  local win = opts.win or vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  if calendar_should_be_active() then
    local calendar = require("cilantro.ui.calendar")
    calendar.open_pair({ win = win })
  else
    M.render()
  end
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
  local fields = { "end_time", "created_at", "updated_at", "title", "status", "start_time" }
  vim.ui.select(fields, { prompt = "Sort by:" }, function(choice)
    if not choice then
      return
    end
    M.query_opts.sort_by = choice
    if M.is_visible() and calendar_should_be_active() then
      local calendar = require("cilantro.ui.calendar")
      if not calendar.is_visible() then
        local list_win = M.get_win()
        if list_win then
          calendar.open_pair({ win = list_win })
          return
        end
      end
    end
    M.render()
  end)
end

function M.toggle_sort_direction()
  M.query_opts.sort_desc = not M.query_opts.sort_desc
  M.render()
end

function M.sort_by_end_date()
  M.query_opts.sort_by = "end_time"
  if M.is_visible() and calendar_should_be_active() then
    local calendar = require("cilantro.ui.calendar")
    if not calendar.is_visible() then
      local list_win = M.get_win()
      if list_win then
        calendar.open_pair({ win = list_win })
        return
      end
    end
  end
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

  map(km.create_event, function()
    require("cilantro").create_event()
  end, "Create new event")

  map(km.delete, function()
    local t = M.get_cursor_task()
    if t then
      require("cilantro").delete(t)
    end
  end, "Delete task")

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
