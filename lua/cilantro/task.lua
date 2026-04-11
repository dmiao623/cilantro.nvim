local config = require("cilantro.config")
local id = require("cilantro.id")
local frontmatter = require("cilantro.frontmatter")

local M = {}

function M.slugify(title)
  local slug = title:lower()
  slug = slug:gsub("[^%w%s-]", "")
  slug = slug:gsub("%s+", "-")
  slug = slug:gsub("%-+", "-")
  slug = slug:gsub("^%-", "")
  slug = slug:gsub("%-$", "")
  if #slug > 50 then
    slug = slug:sub(1, 50):gsub("%-$", "")
  end
  return slug
end

function M.make_filename(title)
  return M.slugify(title) .. ".md"
end

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%S") .. "Z"
end

local function today_iso()
  return os.date("%Y-%m-%d")
end

local function normalize_subtasks(raw)
  if not raw then
    return {}
  end
  local result = {}
  local cfg = config.get()
  for _, item in ipairs(raw) do
    if type(item) == "string" then
      table.insert(result, { name = item, status = cfg.default_status })
    elseif type(item) == "table" then
      table.insert(result, {
        name = item.name or "(unnamed)",
        status = item.status or cfg.default_status,
      })
    end
  end
  return result
end

local function build_task(metadata, path, body_lines)
  return {
    id = metadata.id,
    title = metadata.title,
    status = metadata.status,
    created_at = metadata.created_at,
    updated_at = metadata.updated_at,
    start_date = metadata.start_date,
    end_date = metadata.end_date,
    completed_at = metadata.completed_at,
    estimated_minutes = metadata.estimated_minutes and tonumber(metadata.estimated_minutes),
    subtasks = normalize_subtasks(metadata.subtasks),
    path = path,
    body_lines = body_lines,
  }
end

function M.from_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then
    return nil, "could not read file: " .. path
  end
  return M.from_lines(lines, path)
end

function M.from_lines(lines, path)
  local metadata, _, body_lines = frontmatter.parse(lines)
  if not metadata.id then
    return nil, "missing id in frontmatter: " .. (path or "unknown")
  end
  if not metadata.title then
    return nil, "missing title in frontmatter: " .. (path or "unknown")
  end
  return build_task(metadata, path, body_lines), nil
end

function M.create(title, dir, overrides)
  overrides = overrides or {}
  local cfg = config.get()

  local task_id = id.generate()
  local now = now_iso()

  local metadata = {
    id = task_id,
    title = title,
    status = overrides.status or cfg.default_status,
    created_at = now,
    updated_at = now,
    start_date = overrides.start_date or today_iso(),
    end_date = overrides.end_date,
    completed_at = overrides.completed_at,
    estimated_minutes = overrides.estimated_minutes,
  }

  local filename = M.make_filename(title)
  local path = dir .. "/" .. filename

  local lines = frontmatter.serialize(metadata)
  table.insert(lines, "")

  vim.fn.writefile(lines, path)

  return build_task(metadata, path, { "" })
end

function M.update(task, changes)
  local ok, lines = pcall(vim.fn.readfile, task.path)
  if not ok or not lines then
    error("cilantro: could not read task file: " .. task.path)
  end

  local metadata, _, _ = frontmatter.parse(lines)

  for key, value in pairs(changes) do
    metadata[key] = value
  end

  metadata.updated_at = now_iso()

  if changes.status == "done" and not changes.completed_at then
    metadata.completed_at = now_iso()
  end

  if changes.status and changes.status ~= "done" then
    metadata.completed_at = nil
  end

  local new_lines = frontmatter.replace_frontmatter(lines, metadata)
  vim.fn.writefile(new_lines, task.path)

  local updated_task = M.from_lines(new_lines, task.path)
  return updated_task
end

return M
