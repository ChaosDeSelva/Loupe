-- Optional window controls. Never changes a host window until explicitly called.
local M = {}
M.presets = { { 960, 600 }, { 1280, 800 }, { 1440, 900 }, { 1920, 1200 } }
function M.toggleFullscreen()
  return love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
end
function M.setSize(width, height)
  assert(
    type(width) == "number"
      and type(height) == "number"
      and width >= 1
      and height >= 1
      and width % 1 == 0
      and height % 1 == 0,
    "positive integer dimensions required"
  )
  local _, _, flags = love.window.getMode()
  flags.fullscreen, flags.resizable, flags.highdpi = false, true, true
  return love.window.setMode(width, height, flags)
end
function M.cycleSize()
  local width, height = love.window.getMode()
  local nextIndex = 1
  for i, preset in ipairs(M.presets) do
    if width == preset[1] and height == preset[2] then
      nextIndex = i % #M.presets + 1
    end
  end
  return M.setSize(M.presets[nextIndex][1], M.presets[nextIndex][2])
end
return M
