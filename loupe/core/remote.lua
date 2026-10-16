-- Bounded access to registered data. No evaluation, function calls, or new fields.
local M = {}
M.__index = M
local function finite(value)
  return value == value and value ~= math.huge and value ~= -math.huge
end
local function snapshot(value, depth, seen, budget)
  local kind = type(value)
  if kind == "number" then
    return finite(value) and value or "<non-finite>"
  elseif kind == "string" then
    return value:sub(1, 2048)
  elseif kind == "boolean" then
    return value
  elseif kind ~= "table" then
    return "<" .. kind .. ">"
  end
  if seen[value] then
    return "<cycle>"
  end
  if depth >= 4 then
    return "<table: inspect this path to expand>"
  end
  seen[value] = true
  local out, count = {}, 0
  for key, item in next, value do
    if type(key) == "string" or type(key) == "number" then
      count = count + 1
      budget.n = budget.n + 1
      if count > 100 or budget.n > 500 then
        out["<truncated>"] = true
        break
      end
      out[tostring(key)] = snapshot(item, depth + 1, seen, budget)
    end
  end
  seen[value] = nil
  return out
end
function M.new(opts)
  return setmetatable(opts, M)
end
function M:resolve(name, keys, parent)
  local root
  for _, entry in ipairs(self.roots()) do
    if entry.name == name then
      root = entry.value
      break
    end
  end
  assert(type(root) == "table", "unknown or unavailable watched root")
  assert(type(keys) == "table" and #keys <= 16, "path must have at most 16 keys")
  local current = root
  for i = 1, #keys - (parent and 1 or 0) do
    assert(type(keys[i]) == "string" or type(keys[i]) == "number", "invalid path key")
    assert(type(current) == "table", "path crosses a scalar")
    current = rawget(current, keys[i])
  end
  return current
end
function M:call(action, root, keys, value)
  keys = keys or {}
  if action == "status" then
    local names = {}
    for _, entry in ipairs(self.roots()) do
      names[#names + 1] = entry.name
    end
    return { roots = names, paused = self.clock.paused, scale = self.clock.scale }
  elseif action == "inspect" then
    return snapshot(self:resolve(root, keys), 0, {}, { n = 0 })
  elseif action == "set" then
    assert(#keys > 0, "cannot replace a root")
    local target, key = self:resolve(root, keys, true), keys[#keys]
    assert(type(target) == "table", "parent is not a table")
    local old = rawget(target, key)
    local kind = type(old)
    assert(
      kind == "number" or kind == "string" or kind == "boolean",
      "field is not an existing scalar"
    )
    assert(type(value) == kind, "new value must retain the field type")
    assert(kind ~= "number" or finite(value), "number must be finite")
    assert(kind ~= "string" or #value <= 2048, "string too long")
    self.edits:set(target, key, value, { root = root, keys = keys })
    return { changed = true, value = value }
  elseif action == "pause" or action == "resume" then
    self.clock.paused = action == "pause"
    self.clock.pendingSteps = 0
  elseif action == "step" then
    self.clock:step()
  elseif action == "undo" or action == "redo" then
    self.edits[action](self.edits)
  elseif action == "open" or action == "close" then
    self.setOpen(action == "open")
  elseif action == "save" then
    local ok, detail = self.save()
    assert(ok, detail or "save failed")
    return { saved = true, location = detail }
  else
    error("unsupported action")
  end
  return { ok = true }
end
return M
