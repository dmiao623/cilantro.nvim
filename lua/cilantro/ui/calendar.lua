local config = require("cilantro.config")
local index = require("cilantro.index")
local datetime = require("cilantro.datetime")

local M = {}

M.bufnr = nil
M.event_ids = {}
M.tree_win = nil
M.layout_augroup = nil

local ns = vim.api.nvim_create_namespace("CilantroCalendar")

local function pad_right(str, width)
  if vim.fn.strdisplaywidth(str) >= width then
    return str
  end
  return str .. string.rep(" ", width - vim.fn.strdisplaywidth(str))
end

function M.get_buf()
  if M.bufnr and vim.api.nvim_buf_is_valid(M.bufnr) then
    return M.bufnr
  end

  M.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = M.bufnr })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = M.bufnr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = M.bufnr })
  vim.api.nvim_set_option_value("filetype", "cilantro-calendar", { buf = M.bufnr })
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.bufnr })

  M.setup_keymaps(M.bufnr)

  return M.bufnr
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

function M.get_cursor_event()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local eid = M.event_ids[row]
  if not eid then
    return nil
  end
  return index.events[eid]
end

local function render_event_line(e, width)
  local time = datetime.format_time(e.start_time)
  local prefix = time and ("  " .. time .. "  ") or "        "
  local title = e.title or "(untitled)"
  local line = prefix .. title
  if e.recurring then
    line = line .. " \xe2\x86\xbb " .. e.recurring
  end
  return pad_right(line, width)
end

local function event_line_highlights(e, line_idx)
  local time = datetime.format_time(e.start_time)
  local hls = {}
  if time then
    table.insert(hls, { line_idx, "CilantroEventTime", 2, 7 })
    table.insert(hls, { line_idx, "CilantroTitle", 9, -1 })
  else
    table.insert(hls, { line_idx, "CilantroTitle", 8, -1 })
  end
  return hls
end

-- Group events by start_time date.
local function group_events_by_date(events)
  local groups = {}
  local order = {}
  for _, e in ipairs(events) do
    local d = datetime.date_of(e.start_time)
    if d then
      if not groups[d] then
        groups[d] = {}
        table.insert(order, d)
      end
      table.insert(groups[d], e)
    end
  end
  return groups, order
end

-- Group tasks by end_time date.
local function group_tasks_by_date(tasks)
  local groups = {}
  local order = {}
  for _, t in ipairs(tasks) do
    local d = datetime.date_of(t.end_time) or "No end date"
    if not groups[d] then
      groups[d] = {}
      table.insert(order, d)
    end
    table.insert(groups[d], t)
  end
  return groups, order
end

-- Merge two date-order arrays, deduped, preserving sort order (with "No end date" last).
local function merge_dates(a, b)
  local seen = {}
  local combined = {}
  for _, d in ipairs(a) do
    if not seen[d] then
      seen[d] = true
      table.insert(combined, d)
    end
  end
  for _, d in ipairs(b) do
    if not seen[d] then
      seen[d] = true
      table.insert(combined, d)
    end
  end
  table.sort(combined, function(x, y)
    if x == "No end date" then
      return false
    end
    if y == "No end date" then
      return true
    end
    return x < y
  end)
  return combined
end

function M.render_pair()
  local list = require("cilantro.ui.list")
  local cal_buf = M.get_buf()

  local cal_win = M.get_win()
  local width
  if cal_win then
    width = vim.api.nvim_win_get_width(cal_win)
  else
    local cfg = config.get()
    width = (cfg.calendar and cfg.calendar.width) or 28
  end

  local tasks = list.get_visible_tasks()
  local events = index.query_events()

  local event_groups, event_order = group_events_by_date(events)
  local task_groups, task_order = group_tasks_by_date(tasks)
  local all_dates = merge_dates(event_order, task_order)

  local left_lines, right_lines = {}, {}
  local event_ids, task_ids, subtask_idx = {}, {}, {}
  local left_hls, right_hls = {}, {}
  local line_idx = 0

  local function push(left_line, right_line, eid, tid, sub_i, left_hl_list, right_hl_list)
    table.insert(left_lines, left_line)
    table.insert(right_lines, right_line)
    table.insert(event_ids, eid or false)
    table.insert(task_ids, tid or false)
    if sub_i then
      subtask_idx[#task_ids] = sub_i
    end
    if left_hl_list then
      for _, hl in ipairs(left_hl_list) do
        table.insert(left_hls, hl)
      end
    end
    if right_hl_list then
      for _, hl in ipairs(right_hl_list) do
        table.insert(right_hls, hl)
      end
    end
    line_idx = line_idx + 1
  end

  if #all_dates == 0 then
    vim.api.nvim_set_option_value("modifiable", true, { buf = cal_buf })
    vim.api.nvim_buf_clear_namespace(cal_buf, ns, 0, -1)
    vim.api.nvim_buf_set_lines(cal_buf, 0, -1, false, { pad_right("  No events.", width) })
    vim.api.nvim_set_option_value("modifiable", false, { buf = cal_buf })

    list.render_solo()
    M.event_ids = { false }
    return
  end

  for date_i, date in ipairs(all_dates) do
    if date_i > 1 then
      push("", "", false, false, nil, nil, nil)
    end

    local header_text = "── " .. date .. " ──"
    local left_header = pad_right(header_text, width)
    push(
      left_header,
      header_text,
      false,
      false,
      nil,
      { { line_idx, "CilantroHeader", 0, -1 } },
      { { line_idx, "CilantroHeader", 0, -1 } }
    )

    local evs = event_groups[date] or {}
    local tks = task_groups[date] or {}

    local task_rows_index = 0
    local i = 0
    while i < #evs or task_rows_index < #tks do
      i = i + 1
      local ev = evs[i]
      task_rows_index = task_rows_index + 1
      local tk = tks[task_rows_index]

      local left, right = "", ""
      local eid, tid = false, false
      local left_hl, right_hl = nil, nil

      if ev then
        left = render_event_line(ev, width)
        eid = ev.id
        left_hl = event_line_highlights(ev, line_idx)
      else
        left = pad_right("", width)
      end

      if tk then
        right = list.render_task_line(tk, { show_date = false })
        tid = tk.id
        right_hl = list.task_line_highlights(tk, line_idx, { show_date = false })
      end

      push(left, right, eid, tid, nil, left_hl, right_hl)

      if tk and tk.subtasks then
        for si, subtask in ipairs(tk.subtasks) do
          local sub_left = pad_right("", width)
          local sub_right = list.render_subtask_line(subtask)
          push(sub_left, sub_right, false, tk.id, si, nil, list.subtask_line_highlights(subtask, line_idx))
        end
      end
    end
  end

  -- Apply to calendar buffer
  vim.api.nvim_set_option_value("modifiable", true, { buf = cal_buf })
  vim.api.nvim_buf_clear_namespace(cal_buf, ns, 0, -1)
  vim.api.nvim_buf_set_lines(cal_buf, 0, -1, false, left_lines)
  for _, hl in ipairs(left_hls) do
    vim.api.nvim_buf_add_highlight(cal_buf, ns, hl[2], hl[1], hl[3], hl[4])
  end
  vim.api.nvim_set_option_value("modifiable", false, { buf = cal_buf })

  -- Apply to list buffer
  list.apply_render(right_lines, right_hls, task_ids, subtask_idx)

  M.event_ids = event_ids
end

-- Open the file tree panel rooted at task_dir, split left of `right_of_win`.
-- The command is taken from cfg.layout.file_tree: "netrw" runs :Explore, any
-- other value is run as an Ex command (e.g. "Oil" runs :Oil).
-- Returns the tree window, or nil when the tree command failed.
function M.open_tree(right_of_win)
  local cfg = config.get()
  local tree = (cfg.layout and cfg.layout.file_tree) or "netrw"

  vim.api.nvim_set_current_win(right_of_win)
  vim.cmd("leftabove vsplit")
  local tree_win = vim.api.nvim_get_current_win()

  local ex = (tree == "netrw") and "Explore" or tree
  local cmd = ex .. " " .. vim.fn.fnameescape(cfg.task_dir)
  local ok, err = pcall(vim.cmd, cmd)
  if not ok then
    vim.notify(
      "cilantro: file tree command failed (:" .. cmd .. "): " .. tostring(err),
      vim.log.levels.WARN
    )
    pcall(vim.api.nvim_win_close, tree_win, true)
    M.tree_win = nil
    return nil
  end

  M.tree_win = tree_win

  -- Make the close keymap work from the file tree panel too.
  local km = cfg.keymaps
  if km.close and km.close ~= false then
    local tree_buf = vim.api.nvim_win_get_buf(tree_win)
    vim.keymap.set("n", km.close, function()
      require("cilantro").close()
    end, { buffer = tree_buf, nowait = true, desc = "Close cilantro" })
  end

  return tree_win
end

-- Size the panels according to cfg.layout.ratio. The list window keeps the
-- remaining width, so only the tree and calendar widths are set explicitly.
function M.apply_layout_widths(tree_win, cal_win)
  local cfg = config.get()
  local ratio = (cfg.layout and cfg.layout.ratio) or { 1, 2, 2 }
  local r_tree = tonumber(ratio[1]) or 1
  local r_cal = tonumber(ratio[2]) or 2
  local r_list = tonumber(ratio[3]) or 2

  local has_tree = tree_win and vim.api.nvim_win_is_valid(tree_win)
  local nwin = has_tree and 3 or 2
  local avail = vim.o.columns - (nwin - 1)
  if avail < nwin then
    return
  end

  if has_tree then
    local sum = r_tree + r_cal + r_list
    vim.api.nvim_win_set_width(tree_win, math.max(1, math.floor(avail * r_tree / sum)))
    vim.api.nvim_win_set_width(cal_win, math.max(1, math.floor(avail * r_cal / sum)))
  else
    local sum = r_cal + r_list
    vim.api.nvim_win_set_width(cal_win, math.max(1, math.floor(avail * r_cal / sum)))
  end
end

-- Tear down the whole layout (file tree window + its WinClosed watcher).
function M.teardown_layout()
  if M.layout_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, M.layout_augroup)
    M.layout_augroup = nil
  end
  if M.tree_win and vim.api.nvim_win_is_valid(M.tree_win) then
    pcall(vim.api.nvim_win_close, M.tree_win, false)
  end
  M.tree_win = nil
end

-- Closing the file tree panel tears down the whole cilantro UI.
local function setup_layout_autocmd(tree_win)
  if not (tree_win and vim.api.nvim_win_is_valid(tree_win)) then
    return
  end
  M.layout_augroup = vim.api.nvim_create_augroup("CilantroLayout", { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = M.layout_augroup,
    pattern = tostring(tree_win),
    callback = function()
      vim.schedule(function()
        require("cilantro").close()
      end)
    end,
  })
end

function M.open_pair(opts)
  opts = opts or {}

  local list = require("cilantro.ui.list")
  local list_buf = list.get_buf()
  local target_win = opts.win or vim.api.nvim_get_current_win()

  -- List buffer in the rightmost (target) window
  vim.api.nvim_win_set_buf(target_win, list_buf)

  -- Calendar split immediately left of the list
  vim.api.nvim_set_current_win(target_win)
  vim.cmd("leftabove vsplit")
  local cal_win = vim.api.nvim_get_current_win()
  local cal_buf = M.get_buf()
  vim.api.nvim_win_set_buf(cal_win, cal_buf)

  -- File tree split immediately left of the calendar (reuse if still open)
  local tree_win = M.tree_win
  if not (tree_win and vim.api.nvim_win_is_valid(tree_win)) then
    tree_win = M.open_tree(cal_win)
  end

  -- Width allocation from the configured ratio
  M.apply_layout_widths(tree_win, cal_win)

  -- Sync scrolling between calendar and list only (the tree scrolls freely)
  vim.api.nvim_set_option_value("scrollbind", true, { win = cal_win })
  vim.api.nvim_set_option_value("cursorbind", true, { win = cal_win })
  vim.api.nvim_set_option_value("wrap", false, { win = cal_win })
  vim.api.nvim_set_option_value("scrollbind", true, { win = target_win })
  vim.api.nvim_set_option_value("cursorbind", true, { win = target_win })
  vim.api.nvim_set_option_value("wrap", false, { win = target_win })

  -- Avoid jump-scroll surprises
  pcall(function()
    vim.opt.scrollopt:remove("jump")
  end)

  setup_layout_autocmd(tree_win)

  M.render_pair()

  -- Cursor lands in the list (right) window by default
  vim.api.nvim_set_current_win(target_win)
end

function M.close()
  local win = M.get_win()
  if win then
    vim.api.nvim_win_close(win, false)
  end
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
    local e = M.get_cursor_event()
    if e then
      require("cilantro.ui.peek").open(e)
    end
  end, "Open event in peek split")

  map(km.create_event, function()
    require("cilantro").create_event()
  end, "Create new event")

  map(km.create, function()
    require("cilantro").create_event()
  end, "Create new event")

  map(km.delete, function()
    local e = M.get_cursor_event()
    if e then
      require("cilantro").delete(e)
    end
  end, "Delete event")

  map(km.refresh, function()
    require("cilantro").refresh()
  end, "Refresh")

  map(km.focus, function()
    local e = M.get_cursor_event()
    if e then
      require("cilantro.ui.peek").open(e, { focus = true })
    end
  end, "Open event in focus mode")

  map(km.close, function()
    require("cilantro").close()
  end, "Close cilantro")

  map(km.toggle_calendar, function()
    require("cilantro.ui.list").toggle_calendar()
  end, "Toggle calendar column")
end

return M
