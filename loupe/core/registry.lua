-- The objects the user asked loupe to watch, by name.
--
-- A target is a table, or a function returning one. Functions are resolved on
-- every read, so a game that replaces its state (`game = newGame()`) stays
-- watched: loupe.watch(function() return game end, "game").
local M = {}
M.__index = M

function M.new()
  return setmetatable({ entries = {} }, M)
end

function M:watch(target, name)
  assert(type(name) == "string", 'loupe.watch: a name is required, e.g. watch(game, "game")')
  local kind = type(target)
  assert(
    kind == "table" or kind == "function",
    "loupe.watch: expected a table or a function returning one, got " .. kind
  )
  for _, entry in ipairs(self.entries) do
    if entry.name == name then
      entry.target = target
      return
    end
  end
  self.entries[#self.entries + 1] = { name = name, target = target }
end

function M:unwatch(name)
  for i, entry in ipairs(self.entries) do
    if entry.name == name then
      table.remove(self.entries, i)
      return
    end
  end
end

-- Returns { { name, value, error? }, ... } with getters resolved. A getter that
-- throws is reported rather than allowed to crash the game's draw.
function M:roots()
  local out = {}
  for i, entry in ipairs(self.entries) do
    local root = { name = entry.name, value = entry.target }
    if type(entry.target) == "function" then
      local ok, result = pcall(entry.target)
      if ok then
        root.value = result
      else
        root.value, root.error = nil, tostring(result)
      end
    end
    out[i] = root
  end
  return out
end

return M
