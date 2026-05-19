local M = {}

M.FIELD_ORDER = {
  "type",
  "id",
  "title",
  "status",
  "created_at",
  "updated_at",
  "start_time",
  "end_time",
  "completed_at",
  "estimated_minutes",
  "recurring",
  "subtasks",
}

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

  local metadata = {}
  local i = 2
  while i <= frontmatter_end - 1 do
    local key, value = lines[i]:match("^([%w_]+):%s*(.*)$")
    if key then
      value = vim.trim(value)
      if value == "" then
        -- Check if next lines are list items (  - item)
        local list_items = {}
        while i + 1 <= frontmatter_end - 1 and lines[i + 1]:match("^%s*-%s+") do
          i = i + 1
          local item_content = lines[i]:match("^%s*-%s+(.+)$")
          if not item_content then
            break
          end
          -- Check if this list item is a key: value pair (map item)
          local item_key, item_val = item_content:match("^([%w_]+):%s*(.*)$")
          if item_key then
            local map = { [item_key] = vim.trim(item_val) }
            -- Collect continuation lines (indented key: value without leading -)
            while i + 1 <= frontmatter_end - 1
              and not lines[i + 1]:match("^%s*-%s+")
              and lines[i + 1]:match("^%s+([%w_]+):%s*(.*)$") do
              i = i + 1
              local k, v = lines[i]:match("^%s+([%w_]+):%s*(.*)$")
              map[k] = vim.trim(v)
            end
            table.insert(list_items, map)
          else
            table.insert(list_items, vim.trim(item_content))
          end
        end
        if #list_items > 0 then
          metadata[key] = list_items
        else
          metadata[key] = nil
        end
      else
        metadata[key] = value
      end
    end
    i = i + 1
  end

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

local MAP_ITEM_KEY_ORDER = { "name", "status" }

local function serialize_value(lines, key, value)
  if value == nil then
    return
  end
  if type(value) == "table" then
    if #value == 0 then
      return
    end
    table.insert(lines, key .. ":")
    for _, item in ipairs(value) do
      if type(item) == "table" then
        local first = true
        local written = {}
        for _, k in ipairs(MAP_ITEM_KEY_ORDER) do
          if item[k] ~= nil then
            if first then
              table.insert(lines, "  - " .. k .. ": " .. tostring(item[k]))
              first = false
            else
              table.insert(lines, "    " .. k .. ": " .. tostring(item[k]))
            end
            written[k] = true
          end
        end
        for k, v in pairs(item) do
          if not written[k] then
            if first then
              table.insert(lines, "  - " .. k .. ": " .. tostring(v))
              first = false
            else
              table.insert(lines, "    " .. k .. ": " .. tostring(v))
            end
          end
        end
      else
        table.insert(lines, "  - " .. tostring(item))
      end
    end
  else
    table.insert(lines, key .. ": " .. tostring(value))
  end
end

function M.serialize(metadata)
  local lines = { "---" }
  for _, key in ipairs(M.FIELD_ORDER) do
    serialize_value(lines, key, metadata[key])
  end

  for key, value in pairs(metadata) do
    local found = false
    for _, ordered_key in ipairs(M.FIELD_ORDER) do
      if key == ordered_key then
        found = true
        break
      end
    end
    if not found then
      serialize_value(lines, key, value)
    end
  end

  table.insert(lines, "---")
  return lines
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
