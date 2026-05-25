local config = require("cilantro.config")
local id = require("cilantro.id")
local frontmatter = require("cilantro.frontmatter")
local task = require("cilantro.task")

local M = {}

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%S") .. "Z"
end

local function build_event(metadata, path, body_lines)
  return {
    id = metadata.id,
    type = "event",
    title = metadata.title,
    created_at = metadata.created_at,
    updated_at = metadata.updated_at,
    start_date = metadata.start_date,
    start_time = metadata.start_time,
    start_tz = metadata.start_tz,
    end_date = metadata.end_date,
    end_time = metadata.end_time,
    end_tz = metadata.end_tz,
    ["repeat"] = metadata["repeat"],
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
  metadata = frontmatter.flatten(metadata)
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
  local cfg = config.get()
  local defaults = config.resolve_defaults(cfg)

  local event_id = id.generate()
  local now = now_iso()

  local metadata = {
    type = "event",
    title = title,
    start_date = overrides.start_date or defaults.start_date,
    start_time = overrides.start_time or defaults.start_time,
    start_tz = overrides.start_tz or defaults.start_tz,
    end_date = overrides.end_date or defaults.end_date,
    end_time = overrides.end_time or defaults.end_time,
    end_tz = overrides.end_tz or defaults.end_tz,
    ["repeat"] = overrides["repeat"],
    id = event_id,
    created_at = now,
    updated_at = now,
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
  metadata = frontmatter.flatten(metadata)

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
