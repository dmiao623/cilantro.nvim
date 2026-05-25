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

-- Reassemble split date/time/tz components into a combined datetime string.
-- compose("2026-04-05", "09:00", "-04:00") -> "2026-04-05T09:00-04:00"
-- compose("2026-04-05", "09:00")           -> "2026-04-05T09:00"
-- compose("2026-04-05")                    -> "2026-04-05"
function M.compose(date, time, tz)
  if not date or date == "" then
    return nil
  end
  local result = date
  if time and time ~= "" then
    result = result .. "T" .. time
  end
  if tz and tz ~= "" then
    result = result .. tz
  end
  return result
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

-- Compose split fields and normalize for start comparison.
function M.start_of_parts(date, time)
  if not date or date == "" then
    return nil
  end
  return date .. "T" .. (time or "00:00")
end

-- Compose split fields and normalize for end comparison.
function M.end_of_parts(date, time)
  if not date or date == "" then
    return nil
  end
  return date .. "T" .. (time or "23:59")
end

-- Returns a list of "YYYY-MM-DD" strings for every calendar day from
-- start_date to end_date, inclusive.
function M.enumerate_dates(start_date, end_date)
  if not start_date or start_date == "" then
    return {}
  end
  -- Accept either a plain date or a combined datetime (extract date part).
  local sd = M.date_of(start_date) or start_date
  local ed = end_date and (M.date_of(end_date) or end_date) or sd
  if ed < sd then
    ed = sd
  end

  local dates = {}
  local y, mo, d = sd:match("(%d%d%d%d)-(%d%d)-(%d%d)")
  if not y then
    return {}
  end
  local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 })
  while true do
    local current = os.date("%Y-%m-%d", t)
    table.insert(dates, current)
    if current >= ed then
      break
    end
    t = t + 86400
  end
  return dates
end

-- Enumerate dates for a repeating event.
-- period: "day", "week", "month", "year", or a list of day names {"mon","wed"}
-- repeats: integer limit or nil (uses end_date as boundary; safety cap 365)
function M.enumerate_repeat_dates(start_date, end_date, period, repeats)
  if not start_date or start_date == "" then
    return {}
  end

  local y, mo, d = start_date:match("(%d%d%d%d)-(%d%d)-(%d%d)")
  if not y then
    return {}
  end

  local max_count = repeats or 365
  local dates = {}
  local count = 0

  if type(period) == "table" then
    -- Day-of-week list: enumerate day-by-day, include only matching weekdays
    local day_map = { sun = 0, mon = 1, tue = 2, wed = 3, thu = 4, fri = 5, sat = 6 }
    local day_set = {}
    for _, name in ipairs(period) do
      local idx = day_map[name:lower()]
      if idx then
        day_set[idx] = true
      end
    end
    local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 })
    while count < max_count do
      local current = os.date("%Y-%m-%d", t)
      if end_date and end_date ~= "" and current > end_date then
        break
      end
      local wday = tonumber(os.date("%w", t))
      if day_set[wday] then
        table.insert(dates, current)
        count = count + 1
      end
      t = t + 86400
    end
  elseif period == "day" then
    local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 })
    while count < max_count do
      local current = os.date("%Y-%m-%d", t)
      if end_date and end_date ~= "" and current > end_date then
        break
      end
      table.insert(dates, current)
      count = count + 1
      t = t + 86400
    end
  elseif period == "week" then
    local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 })
    while count < max_count do
      local current = os.date("%Y-%m-%d", t)
      if end_date and end_date ~= "" and current > end_date then
        break
      end
      table.insert(dates, current)
      count = count + 1
      t = t + 7 * 86400
    end
  elseif period == "month" then
    local cy, cm, cd = tonumber(y), tonumber(mo), tonumber(d)
    while count < max_count do
      local t = os.time({ year = cy, month = cm, day = cd, hour = 12 })
      local current = os.date("%Y-%m-%d", t)
      if end_date and end_date ~= "" and current > end_date then
        break
      end
      table.insert(dates, current)
      count = count + 1
      cm = cm + 1
      if cm > 12 then
        cm = 1
        cy = cy + 1
      end
    end
  elseif period == "year" then
    local cy = tonumber(y)
    while count < max_count do
      local t = os.time({ year = cy, month = tonumber(mo), day = tonumber(d), hour = 12 })
      local current = os.date("%Y-%m-%d", t)
      if end_date and end_date ~= "" and current > end_date then
        break
      end
      table.insert(dates, current)
      count = count + 1
      cy = cy + 1
    end
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
