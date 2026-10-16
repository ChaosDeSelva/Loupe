-- Buffers input events between frames. The UI reads one snapshot per frame,
-- so presses, typed text and keys are each seen exactly once.
local M = {}
M.__index = M

function M.new()
  return setmetatable({
    x = 0,
    y = 0,
    down = false,
    pressed = false,
    released = false,
    wheel = 0,
    -- Text and keys in arrival order: { text = "a" } / { key = "left", shift = true }.
    -- A key carries the modifiers held when it was pressed: shift, and ctrl
    -- (Ctrl, or Cmd on macOS).
    typed = {},
  }, M)
end

function M:setPosition(x, y)
  self.x, self.y = x, y
end

function M:mousemoved(x, y)
  self.x, self.y = x, y
end

-- Only the primary button drives widgets.
function M:mousepressed(x, y, button)
  if button == 1 then
    self.x, self.y = x, y
    self.down = true
    self.pressed = true
  end
end

function M:mousereleased(x, y, button)
  if button == 1 then
    self.x, self.y = x, y
    self.down = false
    self.released = true
  end
end

function M:wheelmoved(_, dy)
  self.wheel = self.wheel + dy
end

function M:textinput(text)
  self.typed[#self.typed + 1] = { text = text }
end

-- mods: { shift = bool, ctrl = bool } held with the key (optional).
function M:keypressed(key, mods)
  mods = mods or {}
  self.typed[#self.typed + 1] = { key = key, shift = mods.shift or nil, ctrl = mods.ctrl or nil }
end

-- Returns this frame's snapshot and clears the one-shot fields.
function M:frame()
  local snapshot = {
    x = self.x,
    y = self.y,
    down = self.down,
    pressed = self.pressed,
    released = self.released,
    wheel = self.wheel,
    typed = self.typed,
  }
  self.pressed, self.released = false, false
  self.wheel, self.typed = 0, {}
  return snapshot
end

return M
