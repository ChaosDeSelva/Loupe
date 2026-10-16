-- A fixed virtual resolution, letterboxed into the window, seen through a
-- camera. toScreen/toWorld are what loupe needs to pick objects correctly.
local M = {}

M.WIDTH, M.HEIGHT = 640, 360

local scale, offsetX, offsetY = 1, 0, 0
local camera = { x = 0, y = 0 }

function M.setCamera(cam)
  camera = cam
end

-- Recompute the letterbox for the current window size. Call it on resize and
-- after toggling fullscreen.
function M.fit(windowW, windowH)
  scale = math.min(windowW / M.WIDTH, windowH / M.HEIGHT)
  offsetX = math.floor((windowW - M.WIDTH * scale) / 2)
  offsetY = math.floor((windowH - M.HEIGHT * scale) / 2)
end

-- Window points per virtual pixel; text uses it to render at full resolution.
function M.getScale()
  return scale
end

function M.toScreen(wx, wy)
  return (wx - camera.x) * scale + offsetX, (wy - camera.y) * scale + offsetY
end

function M.toWorld(sx, sy)
  return (sx - offsetX) / scale + camera.x, (sy - offsetY) / scale + camera.y
end

-- Runs drawFn in virtual-resolution space, clipped to the letterbox.
function M.drawVirtual(drawFn)
  local g = love.graphics
  g.push()
  g.translate(offsetX, offsetY)
  g.scale(scale)
  g.setScissor(offsetX, offsetY, M.WIDTH * scale, M.HEIGHT * scale)
  drawFn()
  g.setScissor()
  g.pop()
end

-- Like drawVirtual, but also scrolled by the camera.
function M.drawWorld(drawFn)
  M.drawVirtual(function()
    love.graphics.translate(-camera.x, -camera.y)
    drawFn()
  end)
end

return M
