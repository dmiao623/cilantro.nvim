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
  for i = 2, frontmatter_end - 1 do
    local key, value = lines[i]:match("^([%w_]+):%s*(.*)$")
    if key then
      value = vim.trim(value)
      if value == "" then
        metadata[key] = nil
      else
        metadata[key] = value
      end
    end
  end

  local body_lines = {}
  for i = frontmatter_end + 1, #lines do
    table.insert(body_lines, lines[i])
  end

  return metadata, frontmatter_end, body_lines
end

function M.serialize(metadata)
  local lines = { "---" }
  for _, key in ipairs(M.FIELD_ORDER) do
    local value = metadata[key]
    if value ~= nil then
      table.insert(lines, key .. ": " .. tostring(value))
    else
      table.insert(lines, key .. ":")
    end
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
      if value ~= nil then
        table.insert(lines, key .. ": " .. tostring(value))
      else
        table.insert(lines, key .. ":")
      end
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
