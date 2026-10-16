-- The bit of UTF-8 handling the UI needs (Lua 5.1 has no utf8 library).
-- Positions are byte offsets between characters: 0 is before the first
-- character, #text is after the last.
local M = {}

local LAST_CHAR = "[%z\1-\127\194-\244][\128-\191]*$"

local function isContinuation(text, i)
  local b = text:byte(i)
  return b ~= nil and b >= 128 and b < 192
end

-- Drops the last character, however many bytes it takes.
function M.dropLast(text)
  return (text:gsub(LAST_CHAR, ""))
end

-- The boundary before the character that ends at pos.
function M.prev(text, pos)
  if pos <= 0 then
    return 0
  end
  pos = pos - 1
  while pos > 0 and isContinuation(text, pos + 1) do
    pos = pos - 1
  end
  return pos
end

-- The boundary after the character that starts at pos.
function M.next(text, pos)
  if pos >= #text then
    return #text
  end
  pos = pos + 1
  while pos < #text and isContinuation(text, pos + 1) do
    pos = pos + 1
  end
  return pos
end

return M
