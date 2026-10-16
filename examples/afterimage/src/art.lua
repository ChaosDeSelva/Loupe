-- Original vector ships and interface icons. Backdrop image handling lives in backdrops.lua.
local A = { illustrated = true }
local sprites = require("src.sprites")
local images, laserAtlas, burstAtlas, exhaustAtlas = {}, nil, nil, nil
local function image(name)
  if not images[name] then
    images[name] = love.graphics.newImage("assets/" .. name .. ".png")
    images[name]:setFilter("linear", "linear")
  end
  return images[name]
end
local function paint(name, x, y, size, rotation)
  local img = image(name)
  local scale = size / math.max(img:getDimensions())
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(
    img,
    x,
    y,
    rotation or 0,
    scale,
    scale,
    img:getWidth() / 2,
    img:getHeight() / 2
  )
end
A.colors = {
  cyan = { 0.36, 0.95, 0.88 },
  orange = { 1, 0.51, 0.27 },
  purple = { 0.77, 0.57, 1 },
  white = { 0.88, 0.95, 0.96 },
  muted = {
    0.40,
    0.53,
    0.60,
  },
}
local fonts = {}
local fontScale = 1
function A.setScale(scale)
  local nextScale = math.max(1, math.ceil(scale * love.window.getDPIScale() * 4) / 4)
  if nextScale == fontScale then
    return
  end
  fontScale = nextScale
  for _, font in pairs(fonts) do
    font:release()
  end
  fonts = {}
end
function A.preload()
  laserAtlas = sprites.load("assets/effects/laser-atlas.png", 2, 2, 16, true)
  burstAtlas = sprites.load("assets/effects/burst-atlas.png", 4, 4, 24, false)
  exhaustAtlas = sprites.load("assets/effects/exhaust-atlas.png", 4, 2, 18, true)
end
function A.font(size, strong)
  local key = strong and (size .. ":strong") or size
  if not fonts[key] then
    local name = strong and "Inter-SemiBold.ttf" or "Inter-Regular.ttf"
    local path = "loupe/fonts/" .. name
    if love.filesystem.getInfo(path) then
      fonts[key] = love.graphics.newFont(path, size, "normal", fontScale)
    else
      local file = assert(io.open(love.filesystem.getSource() .. "/../../" .. path, "rb"))
      local bytes = file:read("*a")
      file:close()
      fonts[key] =
        love.graphics.newFont(love.filesystem.newFileData(bytes, name), size, "normal", fontScale)
    end
  end
  love.graphics.setFont(fonts[key])
end

function A.color(c, alpha)
  if type(c) == "string" then
    c = A.colors[c]
  end
  love.graphics.setColor(c[1], c[2], c[3], alpha or 1)
end
function A.text(text, x, y, size, color)
  A.font(size or 14)
  A.color(color or "white")
  love.graphics.print(text, x, y)
end
function A.line(x, y, x2, y2, c, alpha)
  A.color(c or "cyan", alpha)
  love.graphics.line(x, y, x2, y2)
end
function A.panel(x, y, w, h)
  love.graphics.setColor(0.035, 0.065, 0.087, 0.94)
  love.graphics.rectangle("fill", x, y, w, h, 10, 10)
  love.graphics.setColor(0.14, 0.23, 0.28)
  love.graphics.rectangle("line", x, y, w, h, 10, 10)
end
function A.ship(x, y, scale, tilt, time)
  if A.illustrated then
    exhaustAtlas = exhaustAtlas or sprites.load("assets/effects/exhaust-atlas.png", 4, 2, 18, true)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(tilt or 0)
    sprites.draw(
      exhaustAtlas,
      time or 0,
      0,
      37 * (scale or 1),
      24 * (scale or 1),
      52 * (scale or 1)
    )
    love.graphics.pop()
    paint("sprites/kestrel", x, y, 76 * (scale or 1), tilt)
    return
  end
  local lg = love.graphics
  lg.push()
  lg.translate(x, y)
  lg.rotate(tilt or 0)
  lg.scale(scale or 1)
  A.color("cyan", 0.1)
  lg.ellipse("fill", 0, 15, 30, 42)
  A.color("cyan", 0.4)
  lg.polygon("fill", -7, 15, 0, 45 + math.sin((time or 0) * 35) * 7, 7, 15)
  A.color("white")
  lg.polygon("fill", -3, 15, 0, 32, 3, 15)
  lg.setColor(0.10, 0.23, 0.29)
  lg.polygon("fill", 0, -28, -26, 20, -12, 16, 0, 9, 12, 16, 26, 20)
  A.color("cyan")
  lg.setLineWidth(1.4)
  lg.polygon("line", 0, -28, -26, 20, -12, 16, 0, 9, 12, 16, 26, 20)
  lg.setColor(0.71, 0.87, 0.86)
  lg.polygon("fill", 0, -22, -9, 13, 0, 7, 9, 13)
  lg.setColor(0.04, 0.12, 0.19)
  lg.polygon("fill", 0, -12, -4, 3, 0, 8, 4, 3)
  A.line(-17, 9, -12, -2, "cyan")
  A.line(17, 9, 12, -2, "cyan")
  A.color("orange")
  lg.rectangle("fill", -20, 12, 4, 3)
  lg.rectangle("fill", 16, 12, 4, 3)
  lg.pop()
end
function A.enemy(e)
  if A.illustrated then
    paint(
      "sprites/" .. (e.kind == "boss" and "quiet-engine" or e.kind),
      e.x,
      e.y,
      e.kind == "boss" and 190 or e.r * 3.4,
      e.kind == "weaver" and math.sin(e.age * 2 + e.phase) * 0.15 or 0
    )
    if e.flash > 0 then
      A.color("white", e.flash * 2)
      love.graphics.circle("fill", e.x, e.y, e.r)
    end
    if e.hp < e.maxHp then
      A.color("cyan", 0.8)
      love.graphics.rectangle("fill", e.x - 18, e.y - e.r - 10, 36 * math.max(0, e.hp / e.maxHp), 2)
    end
    return
  end
  local lg = love.graphics
  lg.push()
  lg.translate(e.x, e.y)
  if e.kind == "boss" then
    A.color("orange", 0.12)
    lg.circle("fill", 0, 0, 85)
    lg.setColor(0.12, 0.06, 0.12)
    lg.polygon("fill", -72, -22, -30, -46, 30, -46, 72, -22, 50, 38, 0, 60, -50, 38)
    A.color(e.hp < e.maxHp / 2 and "orange" or "purple")
    lg.setLineWidth(2)
    lg.polygon("line", -72, -22, -30, -46, 30, -46, 72, -22, 50, 38, 0, 60, -50, 38)
    lg.push()
    lg.rotate(e.age * 0.5)
    lg.rectangle("line", -25, -25, 50, 50)
    lg.pop()
    A.color("orange")
    lg.circle("fill", 0, 0, 13)
    A.color("white")
    lg.circle("fill", 0, 0, 5)
    for i = -1, 1, 2 do
      A.line(i * 45, -17, i * 42, 25, "cyan")
      lg.circle("line", i * 51, 3, 12)
    end
  elseif e.kind == "gunner" then
    A.color("orange", 0.15)
    lg.circle("fill", 0, 0, 34)
    lg.setColor(0.15, 0.13, 0.07)
    lg.rectangle("fill", -20, -19, 40, 38, 7, 7)
    A.color("orange")
    lg.rectangle("line", -20, -19, 40, 38, 7, 7)
    lg.polygon("fill", -5, -9, 5, -9, 8, 25, -8, 25)
    A.color("white")
    lg.circle("fill", 0, -5, 4)
  elseif e.kind == "drone" then
    lg.rotate(e.age * 0.25)
    A.color("orange", 0.1)
    lg.circle("fill", 0, 0, 31)
    lg.setColor(0.22, 0.10, 0.08)
    lg.polygon("fill", 0, -23, 20, -12, 20, 12, 0, 23, -20, 12, -20, -12)
    A.color("orange")
    lg.polygon("line", 0, -23, 20, -12, 20, 12, 0, 23, -20, 12, -20, -12)
    for n = 0, 5 do
      local a = n * math.pi / 3
      A.line(math.cos(a) * 12, math.sin(a) * 12, math.cos(a) * 19, math.sin(a) * 19, "orange")
    end
    A.color("orange", 0.9)
    lg.circle("fill", 0, 0, 7)
    A.color("white")
    lg.circle("fill", -2, -2, 2)
  else
    lg.rotate(math.sin(e.age * 2 + e.phase) * 0.35)
    A.color("purple", 0.13)
    lg.ellipse("fill", 0, 0, 32, 22)
    lg.setColor(0.14, 0.09, 0.24)
    lg.polygon("fill", -27, -12, -8, -4, 0, 18, 8, -4, 27, -12, 15, 14, 0, 25, -15, 14)
    A.color("purple")
    lg.polygon("line", -27, -12, -8, -4, 0, 18, 8, -4, 27, -12, 15, 14, 0, 25, -15, 14)
    A.color("white")
    lg.polygon("fill", 0, 3, -4, -4, 0, -10, 4, -4)
  end
  if e.flash > 0 then
    A.color("white", e.flash * 4)
    lg.circle("fill", 0, 0, 20)
  end
  lg.pop()
  if e.hp < e.maxHp then
    A.color("white", 0.5)
    lg.rectangle("fill", e.x - 15, e.y - 31, 30 * math.max(0, e.hp / e.maxHp), 2)
  end
end
-- Layered equipment pictograms: a shared housing, distinct silhouettes, restrained glow.
function A.icon(kind, x, y, size, time)
  if A.illustrated then
    local names = {
      lasers = "beam-splitter",
      split = "beam-splitter",
      power = "pulse-core",
      drive = "vector-drive",
      turbo = "vector-drive",
      magnet = "tractor-lens",
      hull = "hull-patch",
      repair = "hull-patch",
    }
    if names[kind] then
      paint("icons/" .. names[kind], x, y, 82 * (size or 1))
      return
    end
  end
  local lg = love.graphics
  lg.push("all")
  lg.translate(x, y)
  lg.scale(size or 1)
  lg.setLineStyle("smooth")
  lg.setLineJoin("bevel")
  local color = (kind == "lasers" or kind == "split") and "purple"
    or ((kind == "drive" or kind == "turbo") and "orange" or "cyan")
  A.color(color, 0.08)
  lg.rectangle("fill", -29, -29, 58, 58, 14, 14)
  lg.setColor(0.025, 0.055, 0.085)
  lg.rectangle("fill", -24, -24, 48, 48, 11, 11)
  A.color(color, 0.35)
  lg.setLineWidth(1)
  lg.rectangle("line", -24, -24, 48, 48, 11, 11)
  A.color(color, 0.2)
  lg.line(-14, -22, 13, -22)
  if kind == "lasers" or kind == "split" then
    for i = -1, 1 do
      local offset = math.abs(i) * 4
      A.color(color, 0.12)
      lg.rectangle("fill", i * 11 - 4, -18 + offset, 8, 30 - offset, 4, 4)
      A.color(color)
      lg.rectangle("fill", i * 11 - 1.5, -16 + offset, 3, 24 - offset, 1.5, 1.5)
      A.color("white", 0.95)
      lg.rectangle("fill", i * 11 - 0.5, -15 + offset, 1, 19 - offset)
      A.color(color, 0.5)
      lg.rectangle("fill", i * 11 - 3, 11, 6, 6, 2, 2)
    end
  elseif kind == "drive" or kind == "turbo" then
    A.color(color, 0.22)
    lg.polygon("fill", -7, 7, 0, 20, 7, 7)
    A.color(color)
    lg.polygon("fill", -4, 9, 0, 17 + math.sin((time or 0) * 8), 4, 9)
    A.color("white")
    lg.polygon("fill", -2, 9, 0, 14, 2, 9)
    A.color(color, 0.6)
    lg.polygon("fill", -8, -8, -15, 5, -15, 12, -8, 8, 8, 8, 15, 12, 15, 5, 8, -8)
    lg.setColor(0.17, 0.25, 0.31)
    lg.polygon("fill", 0, -19, -7, -6, -7, 8, 7, 8, 7, -6)
    A.color("white", 0.8)
    lg.setLineWidth(1.2)
    lg.line(-7, 7, -7, -6, 0, -19, 7, -6, 7, 7)
    A.color(color)
    lg.rectangle("fill", -3, -5, 6, 8, 3, 3)
  elseif kind == "magnet" then
    A.color(color, 0.18)
    lg.setLineWidth(6)
    lg.arc("line", "open", 0, -3, 12, 0, math.pi)
    A.color(color)
    lg.setLineWidth(3)
    lg.arc("line", "open", 0, -3, 12, 0, math.pi)
    lg.line(-12, -3, -12, -14)
    lg.line(12, -3, 12, -14)
    A.color("white", 0.9)
    lg.rectangle("fill", -14, -15, 4, 5, 1, 1)
    lg.rectangle("fill", 10, -15, 4, 5, 1, 1)
    A.color(color, 0.4)
    lg.setLineWidth(1)
    lg.arc("line", "open", 0, -3, 18, 0.25, math.pi - 0.25)
    A.color(color)
    lg.polygon("fill", 0, -9, -3, -4, 0, 1, 3, -4)
  elseif kind == "hull" or kind == "repair" then
    A.color(color, 0.2)
    lg.rectangle("fill", -16, -16, 32, 32, 7, 7)
    A.color("white")
    lg.rectangle("fill", -4, -12, 8, 24, 2, 2)
    lg.rectangle("fill", -12, -4, 24, 8, 2, 2)
  elseif kind == "power" then
    A.color(color, 0.15)
    lg.circle("fill", 0, 0, 18)
    A.color(color, 0.65)
    lg.setLineWidth(1)
    lg.polygon("line", 0, -19, 16, -9, 16, 9, 0, 19, -16, 9, -16, -9)
    A.color(color)
    lg.polygon("fill", 2, -14, -9, 2, -1, 2, -3, 14, 10, -3, 2, -3)
    A.color("white", 0.9)
    lg.line(2, -12, -5, 0, 1, 0)
  else
    A.color(color)
    lg.polygon("fill", 0, -12, 8, 0, 0, 12, -8, 0)
  end
  lg.pop()
end
function A.background(time, field)
  local lg = love.graphics
  lg.setColor(0.018, 0.027, 0.048)
  lg.rectangle("fill", field.x, field.y, field.w, field.h)
  -- Soft, concentric gas clouds and a distant ringed planet.
  lg.setBlendMode("add")
  for i = 20, 1, -1 do
    lg.setColor(0.014, 0.022, 0.048, 0.20)
    lg.ellipse("fill", field.x + 760, field.y + 270, i * 24, i * 16)
    lg.setColor(0.012, 0.035, 0.030, 0.13)
    lg.ellipse("fill", field.x + 210, field.y + 500, i * 18, i * 24)
  end
  lg.setBlendMode("alpha")
  lg.setColor(0.065, 0.10, 0.15)
  lg.circle("fill", field.x + 792, field.y + 138, 85)
  lg.setColor(0.024, 0.045, 0.071)
  lg.circle("fill", field.x + 810, field.y + 124, 83)
  lg.setColor(0.21, 0.31, 0.37, 0.5)
  lg.push()
  lg.translate(field.x + 792, field.y + 138)
  lg.rotate(-0.45)
  lg.ellipse("line", 0, 0, 132, 28)
  lg.ellipse("line", 0, 2, 130, 29)
  lg.pop()
  for i = 1, 150 do
    local x = field.x + ((i * 179.32) % field.w)
    local y = field.y + ((i * 93.71 + time * (10 + i % 4 * 9)) % field.h)
    local a = 0.18 + (i % 7) / 12
    lg.setColor(0.5, 0.7, 0.8, a)
    lg.rectangle("fill", x, y, i % 9 == 0 and 2 or 1, i % 9 == 0 and 3 or 1)
  end
  lg.setLineWidth(1)
  lg.setColor(0.12, 0.25, 0.29, 0.22)
  for i = 1, 4 do
    local y = field.y + ((i * 170 + time * 28) % field.h)
    lg.line(field.x, y, field.x + 10, y)
    lg.line(field.x + field.w - 10, y, field.x + field.w, y)
  end
end
function A.logo(x, y, width)
  local img = image("afterimage-logo")
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(img, x, y, 0, width / img:getWidth(), width / img:getWidth())
end
function A.laser(b, age)
  if A.illustrated then
    laserAtlas = laserAtlas or sprites.load("assets/effects/laser-atlas.png", 2, 2, 16, true)
    sprites.draw(laserAtlas, age, b.x, b.y, 24, 40, math.atan2(b.vy, b.vx) + math.pi / 2)
  else
    love.graphics.setLineWidth(2)
    A.line(b.x, b.y, b.x - b.vx * 0.015, b.y - b.vy * 0.015, "cyan")
  end
end
function A.burst(effect)
  if not A.illustrated then
    return
  end
  burstAtlas = burstAtlas or sprites.load("assets/effects/burst-atlas.png", 4, 4, 24, false)
  sprites.draw(burstAtlas, effect.age, effect.x, effect.y, effect.size)
end
-- Attachments share the hull transform, so all weapon/drive combinations stay aligned.
function A.loadout(player, beams, turbo, drive, time, upgrades)
  local lg = love.graphics
  lg.push()
  lg.translate(player.x, player.y)
  lg.rotate(player.tilt)
  if turbo or drive > 0 then
    for _, x in ipairs({ -16, 16 }) do
      if A.illustrated then
        paint("sprites/turbo-pod", x, 24, turbo and 64 or 42)
      else
        A.color(turbo and "orange" or "cyan", 0.8)
        lg.polygon("fill", x - 5, 10, x + 5, 10, x + 3, 30, x, turbo and 65 or 40, x - 3, 30)
      end
    end
  end
  A.ship(0, 0, 1, 0, time)
  -- Equipment mounts are paired even when the volley has an even beam count.
  for i = 1, 2 * math.ceil((beams - 1) / 2) do
    local side = i % 2 == 1 and -1 or 1
    local x, y = side * (24 + math.floor((i - 1) / 2) * 11), math.floor((i - 1) / 2) * 7
    if A.illustrated then
      paint("sprites/laser-pod", x, y, 52)
    else
      A.color("purple")
      lg.polygon("fill", x, y - 25, x + 5, y - 10, x + 5, y + 18, x - 5, y + 18, x - 5, y - 10)
      A.line(x, y - 22, x, y + 9, "cyan")
    end
  end
  upgrades = upgrades or {}
  if (upgrades.power or 0) > 0 then
    if A.illustrated then
      paint("icons/pulse-core", 0, 5, 18)
    else
      A.color("cyan")
      lg.polygon("fill", 0, -3, 5, 5, 0, 13, -5, 5)
    end
  end
  if (upgrades.magnet or 0) > 0 then
    if A.illustrated then
      paint("icons/tractor-lens", 0, 22, 23)
    else
      A.color("cyan")
      lg.setLineWidth(2)
      lg.circle("line", 0, 22, 8)
    end
  end
  lg.pop()
end
function A.hostileLaser(b)
  local lg = love.graphics
  local angle = math.atan2(b.vy, b.vx)
  lg.push()
  lg.translate(b.x, b.y)
  lg.rotate(angle)
  lg.setColor(1, 0.035, 0.08, 0.22)
  lg.ellipse("fill", -6, 0, 20, 9)
  lg.setColor(1, 0.07, 0.13, 1)
  lg.polygon("fill", 7, 0, -8, -5, -20, 0, -8, 5)
  lg.setColor(1, 0.7, 0.72, 1)
  lg.setLineWidth(2)
  lg.line(-12, 0, 4, 0)
  lg.pop()
end
return A
