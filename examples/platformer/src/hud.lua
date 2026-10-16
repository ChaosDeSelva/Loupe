-- Coins, time and falls during play, and the title and level-complete
-- screens. All drawn in virtual-screen space with crisp text.
local backdrop = require("src.backdrop")
local text = require("src.text")
local view = require("src.view")

local M = {}

local WHITE = { 1, 1, 1, 1 }
local GOLD = { 1, 0.85, 0.3, 1 }

local titleBackdrop = backdrop.new()
local shownScore, bump = 0, 0

-- 0.1..1, pulsing: for "press a key" prompts.
local function blink(time)
  return 0.55 + 0.45 * math.sin(time * 4)
end

local function clockText(seconds)
  return ("%d:%04.1f"):format(math.floor(seconds / 60), seconds % 60)
end

local function coinIcon(x, y, r)
  local g = love.graphics
  g.setColor(0.85, 0.55, 0.1, 1)
  g.circle("fill", x, y, r, 20)
  g.setColor(1, 0.88, 0.25, 1)
  g.circle("fill", x, y, r * 0.7, 20)
end

function M.update(dt, game)
  -- Pop the coin counter whenever the score changes.
  if game and game.score ~= shownScore then
    shownScore, bump = game.score, 1
  end
  bump = math.max(0, bump - dt * 4)
end

function M.drawPlay(game)
  local W = view.WIDTH
  local size = 14 * (1 + bump * 0.35)
  love.graphics.setColor(0.05, 0.03, 0.1, 0.35)
  love.graphics.rectangle("fill", 6, 6, 96, 22, 6, 6)
  coinIcon(19, 17, 6 * (1 + bump * 0.3))
  text.shadowed(("%d / %d"):format(game.score, game.coinsTotal), 30, 17 - size * 0.62, size, WHITE)
  text.shadowed(clockText(game.time), W - 108, 8, 14, WHITE, "right", 100)
  if game.deaths > 0 then
    text.shadowed(("falls %d"):format(game.deaths), W - 108, 26, 10, WHITE, "right", 100)
  end
end

function M.drawTitle(time)
  local W, H = view.WIDTH, view.HEIGHT
  backdrop.draw(titleBackdrop, time * 40, time)
  local g = love.graphics
  g.setColor(0.2, 0.22, 0.35, 1)
  g.rectangle("fill", 0, 320, W, 40)
  g.setColor(0.45, 0.8, 0.45, 1)
  g.rectangle("fill", 0, 320, W, 4)
  local bounce = math.abs(math.sin(time * 2.2)) * 6
  text.shadowed("PLATFORMER", 0, 92 - bounce, 54, WHITE, "center", W)
  text.shadowed("a loupe example", 0, 160, 14, GOLD, "center", W)
  text.shadowed("press Enter", 0, 220, 18, { 1, 1, 1, blink(time) }, "center", W)
  text.shadowed(
    "arrows / WASD move    space jump    F1 inspect    F11 fullscreen    M mute",
    0,
    H - 22,
    9,
    { 1, 1, 1, 0.8 },
    "center",
    W
  )
end

function M.drawWon(game)
  local W = view.WIDTH
  local t = math.min(1, game.celebration * 2)
  -- Slide the panel in from above with a little overshoot.
  local y = 70 - (1 - t) * 120 + math.sin(t * math.pi) * 8
  local g = love.graphics
  g.setColor(0.08, 0.05, 0.15, 0.55 * t)
  g.rectangle("fill", W / 2 - 150, y, 300, 130, 12, 12)
  text.shadowed("LEVEL COMPLETE!", 0, y + 14, 28, GOLD, "center", W)
  local stats = ("coins %d / %d     time %s     falls %d"):format(
    game.score,
    game.coinsTotal,
    clockText(game.time),
    game.deaths
  )
  text.shadowed(stats, 0, y + 58, 11, WHITE, "center", W)
  if game.score == game.coinsTotal then
    text.shadowed("every coin. nice.", 0, y + 78, 11, GOLD, "center", W)
  end
  local alpha = blink(game.clock) * t
  text.shadowed("Enter to play again", 0, y + 102, 12, { 1, 1, 1, alpha }, "center", W)
end

return M
