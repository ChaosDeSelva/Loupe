-- Writes plain Lua values as Lua source that loads back to equal values.
local reflect = require("loupe.core.reflect")

local M = {}

local FRACTION_FORMATS = { "%.15g", "%.16g" }

local function number(v)
  if v ~= v then
    return "0/0"
  elseif v == math.huge then
    return "1/0"
  elseif v == -math.huge then
    return "-1/0"
  elseif v == 0 then
    return "0" -- %.0f would write -0 as "-0"
  elseif v == math.floor(v) and math.abs(v) < 2 ^ 53 then
    -- Not %d: it goes through a C long, 32 bits on 64-bit Windows. Doubles
    -- hold integers exactly up to 2^53, and %.0f prints them exactly.
    return ("%.0f"):format(v)
  end
  -- 17 digits always read back exactly, but show noise ("0.050000000000000003");
  -- the shortest precision that reads back equal is what a person typed.
  for _, fmt in ipairs(FRACTION_FORMATS) do
    local s = fmt:format(v)
    if tonumber(s) == v then
      return s
    end
  end
  return ("%.17g"):format(v)
end

local write

local function writeTable(t, stack)
  if stack[t] then
    error("loupe.serialize: table contains a cycle")
  end
  stack[t] = true
  local parts = {}
  -- Not `#t`: with holes it's unspecified, and positional items after a hole
  -- would load back at the wrong index. Match reflect.fields' array part.
  local arrayLength = 0
  for i in ipairs(t) do
    arrayLength = i
  end
  for _, f in ipairs(reflect.fields(t)) do
    local value = write(f.value, stack)
    if type(f.key) == "number" and f.key <= arrayLength then
      parts[#parts + 1] = value
    else
      parts[#parts + 1] = f.label .. " = " .. value
    end
  end
  stack[t] = nil

  if #parts == 0 then
    return "{}"
  end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

-- stack: the set of tables being written right now, to catch cycles.
function write(v, stack)
  local t = type(v)
  if t == "number" then
    return number(v)
  elseif t == "string" then
    return ("%q"):format(v)
  elseif t == "boolean" or t == "nil" then
    return tostring(v)
  elseif t == "table" then
    return writeTable(v, stack)
  end
  error("loupe.serialize: can't write a " .. t)
end

function M.value(v)
  return write(v, {})
end

return M
