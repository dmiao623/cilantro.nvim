local M = {}

M.defaults = {
  task_dir = nil,
  status_order = { "todo", "in_progress", "done", "cancelled" },
  default_status = "todo",
  peek_height = 15,
  -- Timezone offset appended to default start/end times (ISO-8601 offset,
  -- e.g. "-04:00" for UTC-4, "+00:00" or "Z" for UTC).
  timezone = "-04:00",
  -- Show a confirmation prompt before deleting a task or event.
  confirm_delete = true,
  show_paths = true,
  list_columns = { "status", "title", "end_time" },
  calendar = {
    enabled = true,
    width = 28,
  },
  layout = {
    -- Width ratio of the three panels: file tree : events : tasks
    ratio = { 1, 2, 2 },
    -- Command used for the file tree panel. "netrw" runs :Explore; any other
    -- value is run as an Ex command (e.g. "Oil" runs :Oil).
    file_tree = "netrw",
  },
  -- Default values for non-metadata fields when creating new entries.
  -- Supports template strings: {{today}}, {{now}}, {{timezone}}
  defaults = {
    start_date = "{{today}}",
    start_time = "00:00",
    start_tz = "{{timezone}}",
    end_date = "{{today}}",
    end_time = "23:59",
    end_tz = "{{timezone}}",
  },
  keymaps = {
    open = "<CR>",
    cycle_status = "x",
    cycle_status_back = "X",
    create = "a",
    create_event = "A",
    delete = "dd",
    filter = "f",
    sort = "s",
    sort_direction = "S",
    sort_end_date = "se",
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

-- Resolve template placeholders in a string value.
function M.resolve_template(value, cfg)
  if type(value) ~= "string" then
    return value
  end
  cfg = cfg or M.get()
  local replacements = {
    ["{{today}}"] = os.date("%Y-%m-%d"),
    ["{{now}}"] = os.date("%H:%M"),
    ["{{timezone}}"] = cfg.timezone or "",
  }
  for pattern, replacement in pairs(replacements) do
    value = value:gsub(vim.pesc(pattern), replacement)
  end
  return value
end

-- Resolve all template strings in the defaults config section.
function M.resolve_defaults(cfg)
  cfg = cfg or M.get()
  local resolved = {}
  local defs = cfg.defaults or {}
  for k, v in pairs(defs) do
    resolved[k] = M.resolve_template(v, cfg)
  end
  return resolved
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
