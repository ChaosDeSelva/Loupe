-- The one way loupe changes game values: applies the change, records it for
-- undo, and tracks it as an override to save.
local history = require("loupe.core.history")
local overrides = require("loupe.core.overrides")
local reflect = require("loupe.core.reflect")

local M = {}
M.__index = M

-- opts.resolveRoot(name): the watched root's current table. With it, undo and
-- redo follow a root that a getter has since replaced (the game restarted)
-- instead of writing to the dead table.
function M.new(opts)
  return setmetatable({
    history = history.new(),
    overrides = overrides.new(),
    savedRevision = 0,
    resolveRoot = opts and opts.resolveRoot,
  }, M)
end

-- meta.root + meta.keys: where the field lives, for saving (optional).
-- meta.gesture: changes sharing a gesture undo together.
-- Returns false when the change was made but can't be saved because a key on
-- the way to it isn't a string or finite number (see overrides.persistable);
-- true otherwise.
function M:set(target, key, value, meta)
  local old = target[key]
  if old == value then
    return true
  end
  target[key] = value
  local persist = meta.root ~= nil and overrides.persistable(meta.keys)
  self.history:record({
    target = target,
    key = key,
    old = old,
    new = value,
    gesture = meta.gesture,
    root = meta.root,
    keys = meta.keys,
    rootValue = meta.root and self.resolveRoot and self.resolveRoot(meta.root),
    persist = persist,
  })
  if persist then
    self.overrides:record(meta.root, meta.keys, old, value)
  end
  return persist or meta.root == nil
end

-- Points the step's changes at the root's current table when it changed.
-- Keeps the old target when the field can't be found there any more.
function M:retarget(step)
  if not (step and self.resolveRoot) then
    return
  end
  for _, c in ipairs(step.changes) do
    local keys = c.root and c.keys
    if keys and #keys > 0 and keys[#keys] == c.key then
      local now = self.resolveRoot(c.root)
      if type(now) == "table" and now ~= c.rootValue then
        local target = reflect.resolveParent(now, keys)
        if type(target) == "table" then
          c.target, c.rootValue = target, now
        end
      end
    end
  end
end

-- Records each saveable change in the step as going from c[from] to c[to].
local function recordOverrides(self, step, from, to)
  for _, c in ipairs(step and step.changes or {}) do
    if c.persist then
      self.overrides:record(c.root, c.keys, c[from], c[to])
    end
  end
end

function M:undo()
  self:retarget(self.history:peekUndo())
  local step = self.history:undo()
  recordOverrides(self, step, "new", "old")
  return step
end

function M:redo()
  self:retarget(self.history:peekRedo())
  local step = self.history:redo()
  recordOverrides(self, step, "old", "new")
  return step
end

function M:dirty()
  return self.history.revision ~= self.savedRevision
end

function M:markSaved()
  self.savedRevision = self.history.revision
end

return M
