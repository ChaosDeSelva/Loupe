-- A small platformer with a camera and a letterboxed virtual resolution, and
-- a string scene state machine. It's loupe's test bed for world picking.
-- Movement (`game.player`), the camera (`game.camera`), effects (`game.fx`)
-- and the scenery (`game.backdrop`) are plain numbers to tune live in loupe.

-- Examples share the repo's copy of loupe (and examples/shared).
local repo = love.filesystem.getSource() .. "/../../"
package.path = repo .. "?.lua;" .. repo .. "?/init.lua;" .. package.path

local loupe = require("loupe")
local sfx = require("examples.shared.sfx")
local smoke = require("examples.shared.smoke")
local window = require("examples.shared.window")

local hud = require("src.hud")
local view = require("src.view")
local world = require("src.world")

local game
local clock = 0
local MAX_DT = 1 / 30 -- a long hitch steps the game this far at most

local scenes = { current = "title", update = {}, draw = {}, keypressed = {} }

function scenes.go(name)
  scenes.current = name
  if name == "play" then
    game = world.new()
    view.setCamera(game.camera)
  end
end

function scenes.update.play(dt)
  if world.update(game, dt) == "won" then
    scenes.current = "won"
  end
end
scenes.update.won = scenes.update.play -- the celebration keeps animating

function scenes.draw.title()
  view.drawVirtual(function()
    hud.drawTitle(clock)
  end)
end

function scenes.draw.play()
  world.draw(game)
  view.drawVirtual(function()
    hud.drawPlay(game)
  end)
end

function scenes.draw.won()
  scenes.draw.play()
  view.drawVirtual(function()
    hud.drawWon(game)
  end)
end

function scenes.keypressed.title(key)
  if key == "return" or key == "kpenter" then
    scenes.go("play")
    sfx.play("start")
  end
end

function scenes.keypressed.play(key)
  if key == "space" or key == "up" or key == "w" then
    world.pressJump(game)
  elseif key == "r" then
    scenes.go("play")
  end
end

scenes.keypressed.won = scenes.keypressed.title

function love.load(args)
  local smokeRun = smoke.start(args)
  view.fit(love.graphics.getDimensions())
  sfx.load({ "jump", "land", "coin", "stomp", "hurt", "win", "pop", "start" })
  if smokeRun then
    scenes.go("play")
    loupe.setOpen(true)
  end
end

function love.resize(w, h)
  view.fit(w, h)
end

function love.update(dt)
  smoke.tick()
  dt = math.min(dt, MAX_DT)
  clock = clock + dt
  if scenes.update[scenes.current] then
    scenes.update[scenes.current](dt)
  end
  hud.update(dt, game)
end

function love.draw()
  -- "all" also restores blend mode and font, so loupe draws on a clean slate.
  love.graphics.push("all")
  love.graphics.clear(0.03, 0.02, 0.06) -- the letterbox bars
  scenes.draw[scenes.current]()
  love.graphics.pop()
end

function love.keypressed(key)
  -- Checked first, so Alt+Enter never also starts or restarts the game.
  if window.isFullscreenKey(key) then
    view.fit(window.toggleFullscreen())
  elseif key == "escape" then
    love.event.quit()
  elseif key == "m" then
    sfx.toggleMute()
  elseif scenes.keypressed[scenes.current] then
    scenes.keypressed[scenes.current](key)
  end
end

loupe.watch(function()
  return game
end, "game")
loupe.watch(sfx.settings, "sound")

-- The camera has a position and size too; keep it from being clicked.
loupe.attach({
  toWorld = view.toWorld,
  toScreen = view.toScreen,
  pickable = function(obj)
    return not (game and obj == game.camera)
  end,
})
