-- Fullscreen toggling shared by the examples. F11 and Alt+Enter are free:
-- loupe's defaults are F1, P, `.`, `[`, `]`, `1` and Ctrl/Cmd+Z/Y/S.
local M = {}

function M.isFullscreenKey(key)
  if key == "f11" then
    return true
  end
  return (key == "return" or key == "kpenter") and love.keyboard.isDown("lalt", "ralt")
end

-- "desktop" fullscreen keeps the desktop resolution, so switching is instant
-- and HiDPI scaling stays the same. Callers refit their layout afterwards:
-- not every platform sends love.resize for a programmatic change.
function M.toggleFullscreen()
  love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
  return love.graphics.getDimensions()
end

return M
