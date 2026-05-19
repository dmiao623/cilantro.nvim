local M = {}

-- Parse a date or datetime string.
-- Returns { date = "YYYY-MM-DD", time = "HH:MM" or nil, has_time = bool }
-- Returns nil if the value cannot be parsed.
function M.parse(value)
  if type(value) ~= "string" or value == "" then
    return nil
  end

  local date = value:match("^(%d%d%d%d%-%d%d%-%d%d)$")
  if date then
    return { date = date, time = nil, has_time = false }
  end

  local d, h, m = value:match("^(%d%d%d%d%-%d%d%-%d%d)[T ](%d%d):(%d%d)")
  if d then
    return { date = d, time = h .. ":" .. m, has_time = true }
  end

  return nil
end

function M.date_of(value)
  local parsed = M.parse(value)
  return parsed and parsed.date or nil
end

function M.format_time(value)
  local parsed = M.parse(value)
  if parsed and parsed.has_time then
    return parsed.time
  end
  return nil
end

-- Normalize to "YYYY-MM-DDTHH:MM" for stable lexicographic compare.
-- date-only values: start uses 00:00, end uses 23:59
function M.start_of(value)
  local parsed = M.parse(value)
  if not parsed then
    return nil
  end
  return parsed.date .. "T" .. (parsed.time or "00:00")
end

function M.end_of(value)
  local parsed = M.parse(value)
  if not parsed then
    return nil
  end
  return parsed.date .. "T" .. (parsed.time or "23:59")
end

-- Today's date with a default start time (00:00) and the given timezone.
function M.default_start(tz)
  return os.date("%Y-%m-%d") .. "T00:00" .. (tz or "")
end

-- Today's date with a default end time (23:59) and the given timezone.
function M.default_end(tz)
  return os.date("%Y-%m-%d") .. "T23:59" .. (tz or "")
end

-- Returns a list of "YYYY-MM-DD" strings for every calendar day from
-- start_value's date to end_value's date, inclusive.
function M.enumerate_dates(start_value, end_value)
  local start_date = M.date_of(start_value)
  if not start_date then
    return {}
  end
  local end_date = M.date_of(end_value) or start_date
  if end_date < start_date then
    end_date = start_date
  end

  local dates = {}
  local y, mo, d = start_date:match("(%d%d%d%d)-(%d%d)-(%d%d)")
  local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 })
  while true do
    local current = os.date("%Y-%m-%d", t)
    table.insert(dates, current)
    if current >= end_date then
      break
    end
    t = t + 86400
  end
  return dates
end

function M.compare(a, b)
  local na = M.start_of(a) or "9999-99-99T99:99"
  local nb = M.start_of(b) or "9999-99-99T99:99"
  if na < nb then
    return -1
  elseif na > nb then
    return 1
  end
  return 0
end

return M
