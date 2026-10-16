-- A camera that eases toward the player and leads in the direction they face,
-- so you see what's coming. It's still clamped to the level.
local M = {}

function M.new(w, h)
  return {
    x = 0,
    y = 0,
    w = w,
    h = h,
    smoothing = 7, -- how fast it catches up; higher is snappier
    lookAhead = 56, -- pixels of lead in the facing direction
    leadSpeed = 2.5, -- how fast the lead swings when you turn around
    lead = 0,
  }
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function target(cam, p, levelW, levelH)
  local tx = p.x + p.w / 2 - cam.w / 2 + cam.lead
  local ty = p.y + p.h / 2 - cam.h / 2
  return clamp(tx, 0, levelW - cam.w), clamp(ty, 0, levelH - cam.h)
end

function M.follow(cam, p, dt, levelW, levelH)
  cam.lead = cam.lead + (p.facing * cam.lookAhead - cam.lead) * math.min(1, dt * cam.leadSpeed)
  local tx, ty = target(cam, p, levelW, levelH)
  -- Exponential smoothing is frame-rate independent, unlike a fixed lerp.
  local k = 1 - math.exp(-cam.smoothing * dt)
  cam.x = clamp(cam.x + (tx - cam.x) * k, 0, levelW - cam.w)
  cam.y = clamp(cam.y + (ty - cam.y) * k, 0, levelH - cam.h)
end

-- Jump straight to the player, for a new level or a respawn.
function M.snap(cam, p, levelW, levelH)
  cam.lead = p.facing * cam.lookAhead
  cam.x, cam.y = target(cam, p, levelW, levelH)
end

return M
