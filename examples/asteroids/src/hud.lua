-- Score, wave and lives, plus the title and game-over screens. Sizes follow
-- the window so the HUD reads the same windowed and fullscreen.
local fonts = require("examples.shared.fonts")
local fx = require("src.fx")
local ship = require("src.ship")

local M = {}

M.BANNER_TIME = 2.5 -- seconds the "WAVE n" banner stays up

local WHITE = { 1, 1, 1, 1 }
local ACCENT = { 0.55, 1, 0.95, 1 }
local WARM = { 1, 0.75, 0.35, 1 }

local shownScore, clock = 0, 0

-- 0.1..1, pulsing: for "press a key" prompts.
local function blink()
  return 0.55 + 0.45 * math.sin(clock * 4)
end

-- The HUD's scale for a w x h window: 1 at 640 points on the short side.
-- Snapped to eighths so dragging the window edge doesn't create a font per pixel.
local function unitFor(w, h)
  return math.floor(math.max(0.75, math.min(w, h) / 640) * 8 + 0.5) / 8
end

-- Text with an additive halo: the same trick as fx.stroke, for type.
local function glowText(text, x, y, limit, align, size, color, alpha)
  local g = love.graphics
  local font = fonts.get(size)
  alpha = alpha or 1
  g.setFont(font)
  local glow = fx.tune.glow
  if glow > 0 then
    g.setBlendMode("add")
    g.setColor(color[1], color[2], color[3], glow * 0.22 * alpha)
    local d = math.max(1, size * 0.06)
    for i = 0, 7 do
      local a = i * math.pi / 4
      g.printf(text, x + math.cos(a) * d, y + math.sin(a) * d, limit, align)
    end
    g.setBlendMode("alpha")
  end
  g.setColor(color[1], color[2], color[3], alpha)
  g.printf(text, x, y, limit, align)
end

function M.update(dt, game)
  clock = clock + dt
  -- Count up toward the real score: the roll is half the reward.
  if game.score < shownScore then
    shownScore = game.score
  end
  shownScore = shownScore + (game.score - shownScore) * math.min(1, dt * 10)
end

local function drawLives(game, x, y, unit)
  local g = love.graphics
  local outline = ship.outline(7 * unit)
  for i = 1, math.min(game.lives, 10) do
    g.push()
    g.translate(x + (i - 1) * 22 * unit, y)
    g.rotate(-math.pi / 2)
    fx.stroke(game.ship.color, function()
      g.polygon("line", outline)
    end)
    g.pop()
  end
end

local function drawPlaying(game, best, w, unit)
  local pad = 18 * unit
  glowText(("%d"):format(math.floor(shownScore + 0.5)), pad, pad, w, "left", 34 * unit, WHITE)
  glowText(("BEST %d"):format(best), pad, pad + 40 * unit, w, "left", 13 * unit, ACCENT, 0.7)
  drawLives(game, pad + 8 * unit, pad + 72 * unit, unit)
  glowText(("WAVE %d"):format(game.wave), 0, pad, w - pad, "right", 20 * unit, ACCENT)
end

-- "WAVE n": fades in fast, holds, fades out.
local function drawBanner(game, w, h, unit)
  local t = game.bannerTime
  local alpha = math.min(1, t * 2, (M.BANNER_TIME - t) * 4)
  glowText(("WAVE %d"):format(game.wave), 0, h * 0.3, w, "center", 48 * unit, WARM, alpha)
end

local function drawTitle(w, h, unit)
  glowText("ASTEROIDS", 0, h * 0.28, w, "center", 84 * unit, ACCENT)
  glowText("a loupe example", 0, h * 0.28 + 96 * unit, w, "center", 18 * unit, WARM, 0.8)
  glowText("PRESS ENTER", 0, h * 0.58, w, "center", 26 * unit, WHITE, blink())
  glowText(
    "ARROWS / WASD fly    SPACE fire    F1 inspect    F11 fullscreen    M mute",
    0,
    h - 48 * unit,
    w,
    "center",
    13 * unit,
    WHITE,
    0.6
  )
end

local function drawGameOver(game, w, h, unit)
  glowText("GAME OVER", 0, h * 0.32, w, "center", 64 * unit, WARM)
  glowText(("score %d"):format(game.score), 0, h * 0.32 + 76 * unit, w, "center", 22 * unit, WHITE)
  glowText("ENTER or R to play again", 0, h * 0.6, w, "center", 20 * unit, WHITE, blink())
end

function M.draw(game, best, w, h)
  local unit = unitFor(w, h)
  if game.state ~= "title" then
    drawPlaying(game, best, w, unit)
  end

  if game.state == "play" and game.bannerTime > 0 then
    drawBanner(game, w, h, unit)
  elseif game.state == "title" then
    drawTitle(w, h, unit)
  elseif game.state == "over" then
    drawGameOver(game, w, h, unit)
  end
end

return M
