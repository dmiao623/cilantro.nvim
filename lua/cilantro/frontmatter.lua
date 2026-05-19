local M = {}

-- Shared top-level fields, in serialization order.
local SHARED_ORDER = {
  "type",
  "id",
  "title",
  "created_at",
  "updated_at",
  "start_time",
  "end_time",
}

-- Fields nested under `task-data:`, in serialization order.
local TASK_DATA_ORDER = { "status", "completed_at", "subtasks" }

-- Fields nested under `event-data:`, in serialization order.
local EVENT_DATA_ORDER = { "recurring" }

local MAP_ITEM_KEY_ORDER = { "name", "status" }

--------------------------------------------------------------------------
-- Parsing
--------------------------------------------------------------------------

local function indent_of(line)
  return #(line:match("^(%s*)"))
end

local function is_blank(line)
  return line:match("^%s*$") ~= nil
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
          map[key] = value
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
              local list, ni = parse_list(lines, j, stop, child_indent)
              map[key] = list
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

  -- Back-compat: earlier versions used start_date / end_date.
  if metadata.start_date and not metadata.start_time then
    metadata.start_time = metadata.start_date
    metadata.start_date = nil
  end
  if metadata.end_date and not metadata.end_time then
    metadata.end_time = metadata.end_date
    metadata.end_date = nil
  end

  local body_lines = {}
  for i = frontmatter_end + 1, #lines do
    table.insert(body_lines, lines[i])
  end

  return metadata, frontmatter_end, body_lines
end

-- Lift `task-data:` / `event-data:` contents to the top level, producing a
-- flat metadata table. Old (already-flat) files pass through unchanged.
function M.flatten(metadata)
  local flat = {}
  for k, v in pairs(metadata) do
    if k ~= "task-data" and k ~= "event-data" then
      flat[k] = v
    end
  end
  for _, container in ipairs({ "task-data", "event-data" }) do
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

local function emit_scalar(out, indent, key, value)
  table.insert(out, indent .. key .. ": " .. tostring(value))
end

local function emit_list(out, indent, key, list)
  table.insert(out, indent .. key .. ":")
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

  local known = {}
  for _, k in ipairs(SHARED_ORDER) do
    known[k] = true
  end
  for _, k in ipairs(TASK_DATA_ORDER) do
    known[k] = true
  end
  for _, k in ipairs(EVENT_DATA_ORDER) do
    known[k] = true
  end

  -- Shared top-level fields.
  for _, key in ipairs(SHARED_ORDER) do
    if has_value(m[key]) then
      emit_scalar(out, "", key, m[key])
    end
  end

  -- Preserve any unrecognised top-level scalar fields.
  for key, value in pairs(m) do
    if not known[key] and type(value) ~= "table" then
      emit_scalar(out, "", key, value)
    end
  end

  -- Type-specific blocks. Both are always written so a file's structure is
  -- identical regardless of `type`; only the block matching `type` is read.
  table.insert(out, "task-data:")
  for _, key in ipairs(TASK_DATA_ORDER) do
    if key == "subtasks" and type(m[key]) == "table" and #m[key] > 0 then
      emit_list(out, "  ", "subtasks", m[key])
    elseif key ~= "subtasks" and m[key] ~= nil and m[key] ~= "" then
      emit_scalar(out, "  ", key, m[key])
    else
      table.insert(out, "  " .. key .. ":")
    end
  end

  table.insert(out, "event-data:")
  for _, key in ipairs(EVENT_DATA_ORDER) do
    if m[key] ~= nil and m[key] ~= "" then
      emit_scalar(out, "  ", key, m[key])
    else
      table.insert(out, "  " .. key .. ":")
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
