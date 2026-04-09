local M = {}

M.FIELD_ORDER = {
  "id",
  "title",
  "status",
  "created_at",
  "updated_at",
  "start_date",
  "end_date",
  "completed_at",
  "estimated_minutes",
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
        while i + 1 <= frontmatter_end - 1 and lines[i + 1]:match("^%s*-%s+(.+)$") do
          i = i + 1
          local item = lines[i]:match("^%s*-%s+(.+)$")
          table.insert(list_items, vim.trim(item))
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

  local body_lines = {}
  for i = frontmatter_end + 1, #lines do
    table.insert(body_lines, lines[i])
  end

  return metadata, frontmatter_end, body_lines
end

local function serialize_value(lines, key, value)
  if type(value) == "table" then
    table.insert(lines, key .. ":")
    for _, item in ipairs(value) do
      table.insert(lines, "  - " .. tostring(item))
    end
  elseif value ~= nil then
    table.insert(lines, key .. ": " .. tostring(value))
  else
    table.insert(lines, key .. ":")
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
