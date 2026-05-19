local config = require("cilantro.config")
local task_mod = require("cilantro.task")
local event_mod = require("cilantro.event")
local frontmatter = require("cilantro.frontmatter")
local datetime = require("cilantro.datetime")

local M = {}

M.tasks = {}
M.events = {}
M.by_path = {}

local watcher_handle = nil
local debounce_timer = nil

local function detect_type(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then
    return nil
  end
  local metadata = frontmatter.parse(lines)
  if metadata.type == "event" then
    return "event"
  end
  return "task"
end

local function load_path(path)
  local kind = detect_type(path)
  if kind == "event" then
    local e = event_mod.from_file(path)
    if e then
      return "event", e
    end
  else
    local t = task_mod.from_file(path)
    if t then
      return "task", t
    end
  end
  return nil, nil
end

function M.build(task_dir)
  task_dir = task_dir or config.get().task_dir
  M.tasks = {}
  M.events = {}
  M.by_path = {}

  local files = vim.fn.glob(task_dir .. "/**/*.md", false, true)
  for _, path in ipairs(files) do
    local kind, item = load_path(path)
    if kind == "task" then
      M.tasks[item.id] = item
      M.by_path[path] = { kind = "task", id = item.id }
    elseif kind == "event" then
      M.events[item.id] = item
      M.by_path[path] = { kind = "event", id = item.id }
    end
  end

  return M
end

function M.put(item)
  if not item or not item.id then
    return
  end
  local kind = item.type or "task"
  local store = kind == "event" and M.events or M.tasks

  for path, entry in pairs(M.by_path) do
    if entry.kind == kind and entry.id == item.id and path ~= item.path then
      M.by_path[path] = nil
    end
  end

  store[item.id] = item
  M.by_path[item.path] = { kind = kind, id = item.id }
end

function M.remove(path)
  local entry = M.by_path[path]
  if not entry then
    return
  end
  if entry.kind == "event" then
    M.events[entry.id] = nil
  else
    M.tasks[entry.id] = nil
  end
  M.by_path[path] = nil
end

function M.refresh_path(path)
  local kind, item = load_path(path)
  if item then
    -- If kind changed for this path, drop the old entry first
    local existing = M.by_path[path]
    if existing and existing.kind ~= kind then
      if existing.kind == "event" then
        M.events[existing.id] = nil
      else
        M.tasks[existing.id] = nil
      end
    end
    M.put(item)
  else
    M.remove(path)
  end
end

function M.query(opts)
  opts = opts or {}
  local cfg = config.get()
  local results = {}

  for _, t in pairs(M.tasks) do
    local include = true

    if opts.status then
      if type(opts.status) == "string" then
        if t.status ~= opts.status then
          include = false
        end
      elseif type(opts.status) == "table" then
        local found = false
        for _, s in ipairs(opts.status) do
          if t.status == s then
            found = true
            break
          end
        end
        if not found then
          include = false
        end
      end
    end

    if include and opts.search and opts.search ~= "" then
      local title_lower = (t.title or ""):lower()
      local search_lower = opts.search:lower()
      if not title_lower:find(search_lower, 1, true) then
        include = false
      end
    end

    if include then
      table.insert(results, t)
    end
  end

  local sort_by = opts.sort_by or "end_time"
  local sort_desc = opts.sort_desc
  if sort_desc == nil then
    sort_desc = false
  end

  local status_index = {}
  for i, s in ipairs(cfg.status_order) do
    status_index[s] = i
  end

  local secondary_sort_by = opts.secondary_sort_by or "title"

  table.sort(results, function(a, b)
    local va, vb
    if sort_by == "status" then
      va = status_index[a.status] or 99
      vb = status_index[b.status] or 99
    elseif sort_by == "estimated_minutes" then
      va = a.estimated_minutes or 0
      vb = b.estimated_minutes or 0
    elseif sort_by == "end_time" then
      va = datetime.end_of(a.end_time) or "9999-99-99T99:99"
      vb = datetime.end_of(b.end_time) or "9999-99-99T99:99"
    elseif sort_by == "start_time" then
      va = datetime.start_of(a.start_time) or "9999-99-99T99:99"
      vb = datetime.start_of(b.start_time) or "9999-99-99T99:99"
    else
      va = a[sort_by] or ""
      vb = b[sort_by] or ""
    end

    if va ~= vb then
      if sort_desc then
        return va > vb
      else
        return va < vb
      end
    end

    local sa = (a[secondary_sort_by] or ""):lower()
    local sb = (b[secondary_sort_by] or ""):lower()
    return sa < sb
  end)

  return results
end

function M.query_events(opts)
  opts = opts or {}
  local results = {}

  for _, e in pairs(M.events) do
    if e.start_time then
      table.insert(results, e)
    end
  end

  table.sort(results, function(a, b)
    local va = datetime.start_of(a.start_time) or "9999-99-99T99:99"
    local vb = datetime.start_of(b.start_time) or "9999-99-99T99:99"
    if va ~= vb then
      return va < vb
    end
    return (a.title or ""):lower() < (b.title or ""):lower()
  end)

  return results
end

function M.get()
  if not next(M.tasks) and not next(M.events) and not M._built then
    M.build()
    M._built = true
  end
  return M
end

function M.watch()
  local cfg = config.get()
  if watcher_handle then
    M.unwatch()
  end

  local handle = vim.uv.new_fs_event()
  if not handle then
    return
  end

  handle:start(cfg.task_dir, { recursive = true }, function(err, filename, _)
    if err then
      return
    end
    if not filename or not filename:match("%.md$") then
      return
    end

    if debounce_timer then
      debounce_timer:stop()
    end

    debounce_timer = vim.uv.new_timer()
    debounce_timer:start(100, 0, vim.schedule_wrap(function()
      local path = cfg.task_dir .. "/" .. filename
      if vim.fn.filereadable(path) == 1 then
        local kind, item = load_path(path)
        if item then
          M.put(item)
        else
          local bufnr = vim.fn.bufnr(path)
          if (bufnr == -1 or not vim.api.nvim_buf_is_loaded(bufnr))
            and (kind == nil or kind == "task") then
            local t = task_mod.bootstrap_file(path)
            if t then
              M.put(t)
            end
          end
        end
      else
        M.remove(path)
      end
      local list_ok, list = pcall(require, "cilantro.ui.list")
      if list_ok and list.is_visible() then
        list.render()
      end
    end))
  end)

  watcher_handle = handle
end

function M.unwatch()
  if watcher_handle then
    watcher_handle:stop()
    watcher_handle = nil
  end
  if debounce_timer then
    debounce_timer:stop()
    debounce_timer = nil
  end
end

return M
