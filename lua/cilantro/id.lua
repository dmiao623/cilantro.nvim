local M = {}

local ENCODING = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
local ENCODING_LEN = #ENCODING

local seeded = false
local last_time = 0
local counter = 0

local function ensure_seed()
  if not seeded then
    math.randomseed(os.clock() * 1e6 + os.time())
    seeded = true
  end
end

local function encode_base32(value, length)
  local result = {}
  for i = length, 1, -1 do
    local idx = (value % ENCODING_LEN) + 1
    result[i] = ENCODING:sub(idx, idx)
    value = math.floor(value / ENCODING_LEN)
  end
  return table.concat(result)
end

local function decode_base32(str)
  local value = 0
  for i = 1, #str do
    local char = str:sub(i, i):upper()
    local idx = ENCODING:find(char, 1, true)
    if not idx then
      return nil
    end
    value = value * ENCODING_LEN + (idx - 1)
  end
  return value
end

function M.generate()
  ensure_seed()

  local now = math.floor(os.time() * 1000 + os.clock() * 1000) % (2 ^ 48)

  if now == last_time then
    counter = counter + 1
  else
    counter = 0
    last_time = now
  end

  local time_part = encode_base32(now + counter, 10)

  local rand = 0
  for _ = 1, 6 do
    rand = rand * ENCODING_LEN + math.random(0, ENCODING_LEN - 1)
  end
  local rand_part = encode_base32(rand, 6)

  return time_part .. rand_part
end

function M.timestamp(id)
  if not id or #id < 10 then
    return nil
  end
  local time_str = id:sub(1, 10)
  local ms = decode_base32(time_str)
  if not ms then
    return nil
  end
  return math.floor(ms / 1000)
end

return M
