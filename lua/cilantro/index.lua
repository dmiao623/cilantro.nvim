local config = require("cilantro.config")
local task_mod = require("cilantro.task")

local M = {}

M.tasks = {}
M.by_path = {}

local watcher_handle = nil
local debounce_timer = nil

function M.build(task_dir)
  task_dir = task_dir or config.get().task_dir
  M.tasks = {}
  M.by_path = {}

  local files = vim.fn.glob(task_dir .. "/**/*.md", false, true)
  for _, path in ipairs(files) do
    local t, err = task_mod.from_file(path)
    if t then
      M.tasks[t.id] = t
      M.by_path[path] = t.id
    end
  end

  return M
end

function M.put(task)
  if not task or not task.id then
    return
  end
  -- Remove old path mapping if task moved
  for path, tid in pairs(M.by_path) do
    if tid == task.id and path ~= task.path then
      M.by_path[path] = nil
    end
  end
  M.tasks[task.id] = task
  M.by_path[task.path] = task.id
end

function M.remove(path)
  local tid = M.by_path[path]
  if tid then
    M.tasks[tid] = nil
    M.by_path[path] = nil
  end
end

function M.refresh_path(path)
  local t, _ = task_mod.from_file(path)
  if t then
    M.put(t)
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

  local sort_by = opts.sort_by or "end_date"
  local sort_desc = opts.sort_desc
  if sort_desc == nil then
    sort_desc = false
  end

  local status_index = {}
  for i, s in ipairs(cfg.status_order) do
    status_index[s] = i
  end

  table.sort(results, function(a, b)
    local va, vb
    if sort_by == "status" then
      va = status_index[a.status] or 99
      vb = status_index[b.status] or 99
    elseif sort_by == "estimated_minutes" then
      va = a.estimated_minutes or 0
      vb = b.estimated_minutes or 0
    elseif sort_by == "end_date" then
      -- Tasks without end_date sort last
      va = a.end_date or "9999-99-99"
      vb = b.end_date or "9999-99-99"
    else
      va = a[sort_by] or ""
      vb = b[sort_by] or ""
    end

    if sort_desc then
      return va > vb
    else
      return va < vb
    end
  end)

  return results
end

function M.get()
  if not next(M.tasks) and not M._built then
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
        M.refresh_path(path)
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
