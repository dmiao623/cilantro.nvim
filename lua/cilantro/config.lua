local M = {}

M.defaults = {
  task_dir = nil,
  status_order = { "todo", "in_progress", "done", "cancelled" },
  default_status = "todo",
  peek_height = 15,
  list_columns = { "status", "title", "end_date", "estimated_minutes" },
  keymaps = {
    open = "<CR>",
    cycle_status = "x",
    cycle_status_back = "X",
    create = "a",
    filter = "f",
    sort = "s",
    sort_direction = "S",
    sort_end_date = "se",
    sort_minutes = "sm",
    sort_alpha = "sa",
    toggle_done = "td",
    toggle_paths = "tp",
    refresh = "R",
    focus = "<C-f>",
    close = "q",
  },
}

M.current = nil

local function deep_merge(base, override)
  local result = {}
  for k, v in pairs(base) do
    if type(v) == "table" and type(override[k]) == "table" then
      result[k] = deep_merge(v, override[k])
    elseif override[k] ~= nil then
      result[k] = override[k]
    else
      result[k] = v
    end
  end
  for k, v in pairs(override) do
    if result[k] == nil then
      result[k] = v
    end
  end
  return result
end

function M.setup(opts)
  opts = opts or {}
  M.current = deep_merge(M.defaults, opts)
  if not M.current.task_dir then
    error("cilantro: task_dir is required in setup()")
  end
  M.current.task_dir = vim.fn.expand(M.current.task_dir)
  return M.current
end

function M.get()
  if not M.current then
    error("cilantro: setup() has not been called")
  end
  return M.current
end

return M
