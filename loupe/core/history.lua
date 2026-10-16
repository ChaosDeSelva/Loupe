-- Undo/redo. Each step holds one or more changes { target, key, old, new }.
--
-- Changes from the same gesture (one mouse press: a drag, or a click then
-- typing) merge into one step, keeping each field's first `old` and latest
-- `new`, so a whole drag undoes at once. Extra fields on a change (root,
-- keys) are kept for callers.
local M = {}
M.__index = M

local DEFAULT_LIMIT = 200 -- steps kept for undo

function M.new(opts)
  return setmetatable({
    undoSteps = {},
    redoSteps = {},
    limit = opts and opts.limit or DEFAULT_LIMIT,
    sealed = false, -- after undo/redo, the top step takes no more merges
    revision = 0, -- bumps on every change, undo and redo
  }, M)
end

local function findChange(step, target, key)
  for _, c in ipairs(step.changes) do
    if c.target == target and c.key == key then
      return c
    end
  end
end

-- Whether change continues the gesture of the step on top of the undo stack.
local function continuesTop(self, top, change)
  return change.gesture ~= nil and not self.sealed and top ~= nil and top.gesture == change.gesture
end

-- change = { target, key, old, new, gesture?, ... }
function M:record(change)
  if change.old == change.new then
    return
  end
  self.revision = self.revision + 1
  self.redoSteps = {}

  local top = self.undoSteps[#self.undoSteps]
  if continuesTop(self, top, change) then
    local existing = findChange(top, change.target, change.key)
    if existing then
      existing.new = change.new
    else
      top.changes[#top.changes + 1] = change
    end
    return
  end

  self.sealed = false
  self.undoSteps[#self.undoSteps + 1] = { gesture = change.gesture, changes = { change } }
  if #self.undoSteps > self.limit then
    table.remove(self.undoSteps, 1)
  end
end

function M:canUndo()
  return #self.undoSteps > 0
end

function M:canRedo()
  return #self.redoSteps > 0
end

-- The step undo() or redo() would apply next, or nil.
function M:peekUndo()
  return self.undoSteps[#self.undoSteps]
end

function M:peekRedo()
  return self.redoSteps[#self.redoSteps]
end

-- Returns the step undone, or nil.
function M:undo()
  local step = table.remove(self.undoSteps)
  if not step then
    return nil
  end
  for i = #step.changes, 1, -1 do
    local c = step.changes[i]
    c.target[c.key] = c.old
  end
  self.redoSteps[#self.redoSteps + 1] = step
  self.sealed = true
  self.revision = self.revision + 1
  return step
end

-- Returns the step redone, or nil.
function M:redo()
  local step = table.remove(self.redoSteps)
  if not step then
    return nil
  end
  for _, c in ipairs(step.changes) do
    c.target[c.key] = c.new
  end
  self.undoSteps[#self.undoSteps + 1] = step
  self.sealed = true
  self.revision = self.revision + 1
  return step
end

return M
