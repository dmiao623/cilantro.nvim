local id = require("cilantro.id")
local frontmatter = require("cilantro.frontmatter")
local task = require("cilantro.task")

local M = {}

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%S") .. "Z"
end

local function today_iso()
  return os.date("%Y-%m-%d")
end

local function build_event(metadata, path, body_lines)
  return {
    id = metadata.id,
    type = "event",
    title = metadata.title,
    created_at = metadata.created_at,
    updated_at = metadata.updated_at,
    start_time = metadata.start_time,
    end_time = metadata.end_time,
    recurring = metadata.recurring,
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
  if metadata.type ~= "event" then
    return nil, "not an event: " .. (path or "unknown")
  end
  if not metadata.id then
    return nil, "missing id in frontmatter: " .. (path or "unknown")
  end
  if not metadata.title then
    return nil, "missing title in frontmatter: " .. (path or "unknown")
  end
  return build_event(metadata, path, body_lines), nil
end

function M.create(title, dir, overrides)
  overrides = overrides or {}

  local event_id = id.generate()
  local now = now_iso()

  local metadata = {
    type = "event",
    id = event_id,
    title = title,
    created_at = now,
    updated_at = now,
    start_time = overrides.start_time or today_iso(),
    end_time = overrides.end_time or today_iso(),
    recurring = overrides.recurring,
  }

  local filename = task.make_filename(title)
  local path = dir .. "/" .. filename

  local lines = frontmatter.serialize(metadata)
  table.insert(lines, "")

  vim.fn.writefile(lines, path)

  return build_event(metadata, path, { "" })
end

function M.update(event, changes)
  local ok, lines = pcall(vim.fn.readfile, event.path)
  if not ok or not lines then
    error("cilantro: could not read event file: " .. event.path)
  end

  local metadata, _, _ = frontmatter.parse(lines)

  for key, value in pairs(changes) do
    metadata[key] = value
  end

  metadata.type = "event"
  metadata.updated_at = now_iso()

  local new_lines = frontmatter.replace_frontmatter(lines, metadata)
  vim.fn.writefile(new_lines, event.path)

  return M.from_lines(new_lines, event.path)
end

return M
