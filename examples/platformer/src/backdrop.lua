-- Parallax scenery drawn in virtual-screen space: a sky gradient, a sun,
-- drifting clouds, and three hill ridges. Each layer scrolls at `factor` times
-- the camera, so far things move slowly and near things fast.
local view = require("src.view")

local M = {}

function M.new()
  return {
    skyTop = { 0.18, 0.2, 0.45, 1 },
    skyBottom = { 1, 0.66, 0.5, 1 },
    sun = { 1, 0.9, 0.6, 1 },
    cloudFactor = 0.15,
    cloudSpeed = 6, -- pixels per second of wind
    layers = {
      { factor = 0.1, base = 215, height = 45, wavelength = 170, color = { 0.42, 0.36, 0.6, 1 } },
      { factor = 0.25, base = 255, height = 30, wavelength = 110, color = { 0.3, 0.27, 0.5, 1 } },
      {
        factor = 0.5,
        base = 295,
        height = 18,
        wavelength = 80,
        trees = true,
        color = { 0.18, 0.2, 0.36, 1 },
      },
    },
  }
end

-- A repeatable 0..1 "random" number per integer, so trees and clouds keep
-- their place as they scroll in and out of view.
local function hash(n)
  local s = math.sin(n * 127.1 + 311.7) * 43758.5453
  return s - math.floor(s)
end

-- Layered sines make a ridge that never visibly repeats.
local function ridge(layer, x, seed)
  local f = 1 / layer.wavelength
  local y = 0.6 * math.sin(x * f + seed) + 0.3 * math.sin(x * f * 2.3 + seed * 1.7)
  return layer.base - layer.height * (y + 0.1 * math.sin(x * f * 5.1 + seed * 3.1))
end

local sky -- a 4-vertex mesh, so the gradient is smooth rather than banded

local function drawSky(bd)
  local g = love.graphics
  local W, H = view.WIDTH, view.HEIGHT
  if not sky then
    sky = g.newMesh(4, "fan", "dynamic")
  end
  local top, bottom = bd.skyTop, bd.skyBottom
  sky:setVertex(1, 0, 0, 0, 0, top[1], top[2], top[3], 1)
  sky:setVertex(2, W, 0, 1, 0, top[1], top[2], top[3], 1)
  sky:setVertex(3, W, H, 1, 1, bottom[1], bottom[2], bottom[3], 1)
  sky:setVertex(4, 0, H, 0, 1, bottom[1], bottom[2], bottom[3], 1)
  g.setColor(1, 1, 1, 1)
  g.draw(sky)
end

local function drawSun(bd)
  local g = love.graphics
  local c = bd.sun
  g.setBlendMode("add")
  for i = 1, 8 do
    g.setColor(c[1], c[2], c[3], 0.05)
    g.circle("fill", 470, 150, 22 + i * 9, 48)
  end
  g.setBlendMode("alpha")
  g.setColor(c)
  g.circle("fill", 470, 150, 24, 48)
end

local function drawClouds(bd, camX, time)
  local g = love.graphics
  local spacing = 190
  local scroll = camX * bd.cloudFactor + time * bd.cloudSpeed
  local first = math.floor(scroll / spacing) - 1
  for k = first, first + math.ceil(view.WIDTH / spacing) + 2 do
    local x = k * spacing - scroll + hash(k) * 80
    local y = 40 + hash(k + 50) * 90
    local s = 0.6 + hash(k + 99) * 0.7
    g.setColor(1, 0.95, 0.95, 0.35 + hash(k + 7) * 0.25)
    g.ellipse("fill", x, y, 34 * s, 9 * s, 24)
    g.ellipse("fill", x - 14 * s, y - 5 * s, 16 * s, 9 * s, 20)
    g.ellipse("fill", x + 10 * s, y - 8 * s, 18 * s, 11 * s, 20)
  end
end

-- Pine silhouettes standing on the ridge, in the layer's color.
local function drawTrees(layer, scroll, seed)
  local spacing = 26
  local first = math.floor(scroll / spacing) - 1
  for k = first, first + math.ceil(view.WIDTH / spacing) + 2 do
    if hash(k) > 0.35 then
      local wx = k * spacing + hash(k + 3) * 12
      local x = wx - scroll
      local base = ridge(layer, wx, seed) + 4
      local h = 18 + hash(k + 11) * 22
      love.graphics.polygon("fill", x - h * 0.28, base, x, base - h, x + h * 0.28, base)
    end
  end
end

local function drawLayer(layer, camX, seed)
  local g = love.graphics
  local scroll = camX * layer.factor
  local H, step = view.HEIGHT, 8
  g.setColor(layer.color)
  -- Thin vertical strips: love.graphics.polygon only fills convex shapes,
  -- and each strip of a ridge is convex even though the ridge isn't.
  local prev = ridge(layer, scroll, seed)
  for x = step, view.WIDTH + step, step do
    local y = ridge(layer, x + scroll, seed)
    g.polygon("fill", x - step, prev, x, y, x, H, x - step, H)
    prev = y
  end
  if layer.trees then
    drawTrees(layer, scroll, seed)
  end
end

function M.draw(bd, camX, time)
  drawSky(bd)
  drawSun(bd)
  drawClouds(bd, camX, time)
  for i, layer in ipairs(bd.layers) do
    drawLayer(layer, camX, i * 1.37)
  end
end

return M
