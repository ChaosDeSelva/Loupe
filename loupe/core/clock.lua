-- Game time control: pause, single-step, and speed presets.
local M = {}
M.__index = M

M.SCALES = { 0.1, 0.25, 0.5, 1, 2, 4 }

function M.new(opts)
  opts = opts or {}
  return setmetatable({
    paused = false,
    scale = 1,
    stepSize = opts.stepSize or 1 / 60,
    pendingSteps = 0,
  }, M)
end

-- Returns the dt to give the game this frame, or nil to skip its update.
-- Skipping (rather than passing 0) matters: games react to input inside
-- update, so a zero-dt update would still fire, jump, etc.
function M:advance(dt)
  if not self.paused then
    return dt * self.scale
  end
  if self.pendingSteps > 0 then
    self.pendingSteps = self.pendingSteps - 1
    return self.stepSize
  end
  return nil
end

function M:togglePause()
  self.paused = not self.paused
  self.pendingSteps = 0
end

-- Steps use a fixed size, ignoring scale, so stepping is reproducible.
function M:step()
  self.paused = true
  self.pendingSteps = self.pendingSteps + 1
end

function M:faster()
  for _, s in ipairs(M.SCALES) do
    if s > self.scale then
      self.scale = s
      return
    end
  end
end

function M:slower()
  for i = #M.SCALES, 1, -1 do
    if M.SCALES[i] < self.scale then
      self.scale = M.SCALES[i]
      return
    end
  end
end

function M:resetScale()
  self.scale = 1
end

return M
