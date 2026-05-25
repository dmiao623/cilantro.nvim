local M = {}

-- Shared top-level fields, in serialization order.
local SHARED_ORDER = {
  "type",
  "title",
  -- blank line inserted after title
  "start_date",
  "start_time",
  "start_tz",
  -- blank line inserted after start_tz
  "end_date",
  "end_time",
  "end_tz",
}

-- Fields nested under `task-data:`, in serialization order.
local TASK_DATA_ORDER = { "status", "completed_at", "subtasks" }

-- Fields nested under `event-data: > repeat:`, in serialization order.
local REPEAT_ORDER = { "enable", "period", "repeats" }

-- The only child of `event-data:` is the `repeat` block.
local EVENT_DATA_ORDER = { "repeat" }

-- Fields nested under `metadata:`, in serialization order.
local METADATA_ORDER = { "id", "created_at", "updated_at" }

local MAP_ITEM_KEY_ORDER = { "name", "status" }

-- Groups of shared keys separated by blank lines in the output.
local SHARED_GROUPS = {
  { "type", "title" },
  { "start_date", "start_time", "start_tz" },
  { "end_date", "end_time", "end_tz" },
}

--------------------------------------------------------------------------
-- Parsing
--------------------------------------------------------------------------

local function indent_of(line)
  return #(line:match("^(%s*)"))
end

local function is_blank(line)
  return line:match("^%s*$") ~= nil
end

-- Try to parse an inline YAML list like "[mon, wed, fri]".
local function try_parse_inline_list(value)
  local inner = value:match("^%[(.*)%]$")
  if not inner then
    return nil
  end
  local items = {}
  for item in inner:gmatch("[^,]+") do
    table.insert(items, vim.trim(item))
  end
  if #items == 0 then
    return nil
  end
  return items
end

local parse_map, parse_list

-- Parse consecutive `- item` list entries at `indent`. Items are either
-- scalars or maps (`- key: value` with deeper-indented continuation lines).
-- Returns the list and the index of the first unconsumed line.
parse_list = function(lines, i, stop, indent)
  local list = {}
  while i <= stop do
    local line = lines[i]
    if is_blank(line) then
      i = i + 1
    elseif indent_of(line) ~= indent or not line:match("^%s*-%s") then
      break
    else
      local rest = line:match("^%s*-%s+(.*)$") or ""
      local item_key, item_val = rest:match("^([%w_%-]+):%s*(.*)$")
      if item_key then
        local map = { [item_key] = vim.trim(item_val) }
        i = i + 1
        -- continuation lines: deeper-indented `key: value`, no leading dash
        while i <= stop do
          local l = lines[i]
          if is_blank(l) then
            i = i + 1
          elseif indent_of(l) <= indent or l:match("^%s*-%s") then
            break
          else
            local k, v = l:match("^%s*([%w_%-]+):%s*(.*)$")
            if not k then
              break
            end
            map[k] = vim.trim(v)
            i = i + 1
          end
        end
        table.insert(list, map)
      else
        table.insert(list, vim.trim(rest))
        i = i + 1
      end
    end
  end
  return list, i
end

-- Parse map entries at `indent`. An empty value followed by a deeper-indented
-- block produces a nested map or list. Returns the map and the index of the
-- first unconsumed line.
parse_map = function(lines, i, stop, indent)
  local map = {}
  while i <= stop do
    local line = lines[i]
    if is_blank(line) then
      i = i + 1
    elseif indent_of(line) ~= indent then
      break
    else
      local key, value = line:match("^%s*([%w_%-]+):%s*(.*)$")
      if not key then
        -- not a recognised entry; skip leniently
        i = i + 1
      else
        value = vim.trim(value)
        if value ~= "" then
          -- Try inline list syntax: [a, b, c]
          local inline = try_parse_inline_list(value)
          if inline then
            map[key] = inline
          else
            map[key] = value
          end
          i = i + 1
        else
          -- empty value: a child block may follow at a deeper indent
          local j = i + 1
          while j <= stop and is_blank(lines[j]) do
            j = j + 1
          end
          if j <= stop and indent_of(lines[j]) > indent then
            local child_indent = indent_of(lines[j])
            if lines[j]:match("^%s*-%s") then
              local list_val, ni = parse_list(lines, j, stop, child_indent)
              map[key] = list_val
              i = ni
            else
              local submap, ni = parse_map(lines, j, stop, child_indent)
              map[key] = submap
              i = ni
            end
          else
            i = i + 1
          end
        end
      end
    end
  end
  return map, i
end

-- Split a combined datetime string into (date, time, tz) components.
-- "2026-04-05T09:00-04:00" -> "2026-04-05", "09:00", "-04:00"
-- "2026-04-05T09:00Z"      -> "2026-04-05", "09:00", "Z"
-- "2026-04-05T09:00"       -> "2026-04-05", "09:00", nil
-- "2026-04-05"             -> "2026-04-05", nil, nil
local function split_datetime(value)
  if type(value) ~= "string" then
    return nil, nil, nil
  end
  local d, t, tz = value:match("^(%d%d%d%d%-%d%d%-%d%d)[T ](%d%d:%d%d)(.+)$")
  if d then
    return d, t, tz
  end
  d, t = value:match("^(%d%d%d%d%-%d%d%-%d%d)[T ](%d%d:%d%d)$")
  if d then
    return d, t, nil
  end
  d = value:match("^(%d%d%d%d%-%d%d%-%d%d)$")
  if d then
    return d, nil, nil
  end
  return nil, nil, nil
end

function M.parse(lines)
  if not lines or #lines == 0 then
    return {}, 0, {}
  end

  if lines[1] ~= "---" then
    return {}, 0, lines
  end

  local frontmatter_end = nil
  for i = 2, #lines do
    if lines[i] == "---" then
      frontmatter_end = i
      break
    end
  end

  if not frontmatter_end then
    return {}, 0, lines
  end

  local metadata = parse_map(lines, 2, frontmatter_end - 1, 0)

  ---------------------------------------------------------------------------
  -- Back-compat: migrate old formats
  ---------------------------------------------------------------------------

  -- Old format used combined start_time / end_time with embedded date+tz.
  -- Also handle even older start_date / end_date aliases.
  if metadata.start_date and not metadata.start_time then
    -- Very old alias: start_date was the combined field
    local d, t, tz = split_datetime(metadata.start_date)
    if d and t then
      metadata.start_date = d
      metadata.start_time = t
      metadata.start_tz = tz
    end
  elseif metadata.start_time and metadata.start_time:match("^%d%d%d%d%-") then
    -- Old combined start_time containing a full date
    local d, t, tz = split_datetime(metadata.start_time)
    if d then
      metadata.start_date = d
      metadata.start_time = t
      metadata.start_tz = tz
    end
  end

  if metadata.end_date and not metadata.end_time then
    local d, t, tz = split_datetime(metadata.end_date)
    if d and t then
      metadata.end_date = d
      metadata.end_time = t
      metadata.end_tz = tz
    end
  elseif metadata.end_time and metadata.end_time:match("^%d%d%d%d%-") then
    local d, t, tz = split_datetime(metadata.end_time)
    if d then
      metadata.end_date = d
      metadata.end_time = t
      metadata.end_tz = tz
    end
  end

  -- Old event-data had a flat `recurring` string; convert to repeat block.
  if type(metadata["event-data"]) == "table" then
    local ed = metadata["event-data"]
    if ed.recurring and not ed["repeat"] then
      ed["repeat"] = { enable = "true", period = ed.recurring, repeats = "" }
      ed.recurring = nil
    end
  end

  local body_lines = {}
  for i = frontmatter_end + 1, #lines do
    table.insert(body_lines, lines[i])
  end

  return metadata, frontmatter_end, body_lines
end

-- Lift `task-data:` / `event-data:` / `metadata:` contents to the top level,
-- producing a flat metadata table. Old (already-flat) files pass through
-- unchanged. The `repeat` key stays as a table if present.
function M.flatten(metadata)
  local flat = {}
  for k, v in pairs(metadata) do
    if k ~= "task-data" and k ~= "event-data" and k ~= "metadata" then
      flat[k] = v
    end
  end
  for _, container in ipairs({ "task-data", "event-data", "metadata" }) do
    local sub = metadata[container]
    if type(sub) == "table" then
      for k, v in pairs(sub) do
        if flat[k] == nil then
          flat[k] = v
        end
      end
    end
  end
  return flat
end

--------------------------------------------------------------------------
-- Serialization
--------------------------------------------------------------------------

-- Compute the column width (max key length) for a set of keys.
local function col_width(keys)
  local max_len = 0
  for _, k in ipairs(keys) do
    if #k > max_len then
      max_len = #k
    end
  end
  return max_len
end

local function emit_aligned(out, indent, key, value, width)
  local padding = string.rep(" ", width - #key)
  table.insert(out, indent .. key .. ":" .. padding .. " " .. tostring(value))
end

local function emit_empty(out, indent, key, width)
  table.insert(out, indent .. key .. ":" .. string.rep(" ", width - #key))
end

local function emit_list(out, indent, key, list, width)
  table.insert(out, indent .. key .. ":" .. string.rep(" ", width - #key))
  local item_width = col_width(MAP_ITEM_KEY_ORDER)
  for _, item in ipairs(list) do
    if type(item) == "table" then
      local first = true
      local written = {}
      local function put(k, v)
        local prefix = first and (indent .. "  - ") or (indent .. "    ")
        table.insert(out, prefix .. k .. ": " .. tostring(v))
        first = false
        written[k] = true
      end
      for _, k in ipairs(MAP_ITEM_KEY_ORDER) do
        if item[k] ~= nil then
          put(k, item[k])
        end
      end
      for k, v in pairs(item) do
        if not written[k] then
          put(k, v)
        end
      end
    else
      table.insert(out, indent .. "  - " .. tostring(item))
    end
  end
end

-- Serialize an inline list like [mon, wed, fri].
local function serialize_inline_list(list)
  return "[" .. table.concat(list, ", ") .. "]"
end

-- Does `value` warrant a line? Empty tables / lists are skipped.
local function has_value(value)
  if value == nil then
    return false
  end
  if type(value) == "table" then
    return #value > 0
  end
  return true
end

function M.serialize(metadata)
  -- Work from a flat view, so callers may pass either shape.
  local m = M.flatten(metadata)
  local out = { "---" }

  -- Track all known keys so we can emit unknown extras.
  local known = {}
  for _, k in ipairs(SHARED_ORDER) do
    known[k] = true
  end
  for _, k in ipairs(TASK_DATA_ORDER) do
    known[k] = true
  end
  for _, k in ipairs(METADATA_ORDER) do
    known[k] = true
  end
  known["repeat"] = true

  -- Shared top-level fields, grouped with blank-line separators.
  local shared_width = col_width(SHARED_ORDER)
  for gi, group in ipairs(SHARED_GROUPS) do
    if gi > 1 then
      table.insert(out, "")
    end
    for _, key in ipairs(group) do
      if has_value(m[key]) then
        emit_aligned(out, "", key, m[key], shared_width)
      else
        emit_empty(out, "", key, shared_width)
      end
    end
  end

  -- Preserve any unrecognised top-level scalar fields.
  for key, value in pairs(m) do
    if not known[key] and type(value) ~= "table" then
      table.insert(out, "")
      emit_aligned(out, "", key, value, #key)
    end
  end

  -- task-data block
  table.insert(out, "")
  local td_width = col_width(TASK_DATA_ORDER)
  table.insert(out, "task-data:")
  for _, key in ipairs(TASK_DATA_ORDER) do
    if key == "subtasks" and type(m[key]) == "table" and #m[key] > 0 then
      emit_list(out, "  ", "subtasks", m[key], td_width)
    elseif key ~= "subtasks" and m[key] ~= nil and m[key] ~= "" then
      emit_aligned(out, "  ", key, m[key], td_width)
    else
      emit_empty(out, "  ", key, td_width)
    end
  end

  -- event-data block with nested repeat
  table.insert(out, "")
  table.insert(out, "event-data:")
  local rep = m["repeat"]
  local rep_width = col_width(REPEAT_ORDER)
  table.insert(out, "  repeat:")
  if type(rep) == "table" then
    for _, key in ipairs(REPEAT_ORDER) do
      local v = rep[key]
      if type(v) == "table" then
        emit_aligned(out, "    ", key, serialize_inline_list(v), rep_width)
      elseif has_value(v) then
        emit_aligned(out, "    ", key, v, rep_width)
      else
        emit_empty(out, "    ", key, rep_width)
      end
    end
  else
    for _, key in ipairs(REPEAT_ORDER) do
      emit_empty(out, "    ", key, rep_width)
    end
  end

  -- metadata block
  table.insert(out, "")
  local meta_width = col_width(METADATA_ORDER)
  table.insert(out, "metadata:")
  for _, key in ipairs(METADATA_ORDER) do
    if has_value(m[key]) then
      emit_aligned(out, "  ", key, m[key], meta_width)
    else
      emit_empty(out, "  ", key, meta_width)
    end
  end

  table.insert(out, "---")
  return out
end

function M.replace_frontmatter(buf_lines, new_metadata)
  local _, _, body_lines = M.parse(buf_lines)

  local new_lines = M.serialize(new_metadata)

  for _, line in ipairs(body_lines) do
    table.insert(new_lines, line)
  end

  return new_lines
end

return M
