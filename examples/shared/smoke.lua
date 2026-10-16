-- `--smoke [frames]`: run unattended for a number of frames, then quit. CI
-- launches every example this way to prove it starts and runs.
local M = {}

local DEFAULT_FRAMES = 120

local framesLeft

-- Reads the flag from love.load's args. Returns true when this is a smoke run.
function M.start(args)
  for i, a in ipairs(args) do
    if a == "--smoke" then
      framesLeft = tonumber(args[i + 1]) or DEFAULT_FRAMES
    end
  end
  return framesLeft ~= nil
end

-- Call once per love.update; quits when the frames run out.
function M.tick()
  if framesLeft then
    framesLeft = framesLeft - 1
    if framesLeft <= 0 then
      love.event.quit(0)
    end
  end
end

return M
