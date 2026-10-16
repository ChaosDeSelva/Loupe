-- Control characters in strings the UI shows or edits. Every text box in
-- loupe is one row tall, so a "\n" drawn as-is would spill over the rows
-- below. oneLine is for showing (lossy, readable); encode/decode are for
-- editing (exact: decode(encode(s)) == s).
local M = {}

local NAMED = { ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local UNNAMED = { n = "\n", r = "\r", t = "\t", ["\\"] = "\\" }

local function numeric(c)
  return ("\\%03d"):format(c:byte())
end

function M.hasControl(str)
  return str:find("%c") ~= nil
end

-- glyphs.newline / glyphs.tab replace "\n" and "\t" (default: "\n", "\t"
-- written out, which any font can draw). Other control characters are
-- written as Lua escapes.
function M.oneLine(str, glyphs)
  if not str:find("%c") then
    return str
  end
  glyphs = glyphs or {}
  return (
    str:gsub("%c", function(c)
      if c == "\n" and glyphs.newline then
        return glyphs.newline
      elseif c == "\t" and glyphs.tab then
        return glyphs.tab
      end
      return NAMED[c] or numeric(c)
    end)
  )
end

-- The editable form: control characters and backslashes as Lua escapes.
function M.encode(str)
  return (
    str:gsub("[%c\\]", function(c)
      if c == "\\" then
        return "\\\\"
      end
      return NAMED[c] or numeric(c)
    end)
  )
end

-- Reads \n, \r, \t, \\ and \ddd (up to 255). Any other backslash is kept as
-- typed, so a stray one never eats the character after it.
function M.decode(str)
  local out, i = {}, 1
  while true do
    local at = str:find("\\", i, true)
    if not at then
      out[#out + 1] = str:sub(i)
      break
    end
    out[#out + 1] = str:sub(i, at - 1)
    local nextChar = str:sub(at + 1, at + 1)
    local digits = str:match("^%d%d?%d?", at + 1)
    if UNNAMED[nextChar] then
      out[#out + 1] = UNNAMED[nextChar]
      i = at + 2
    elseif digits and tonumber(digits) <= 255 then
      out[#out + 1] = string.char(tonumber(digits))
      i = at + 1 + #digits
    else
      out[#out + 1] = "\\"
      i = at + 1
    end
  end
  return table.concat(out)
end

return M
