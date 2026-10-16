-- Source examples use the repository library; packaged games bundle it beside main.lua.
local repo = love.filesystem.getSource() .. "/../../"
package.path = repo .. "?.lua;" .. repo .. "?/init.lua;" .. package.path
local sim = require("src.sim")
local art = require("src.art")
local audio = require("src.audio")
local window = require("loupe.window")
local browserBuild = false -- Replaced only by the web exporter.
local browserWidth, browserHeight = nil, nil
local backdrops = require("src.backdrops")
local analytics = require("src.analytics")
local settings = require("src.settings")
local version = require("src.version")
local lg = love.graphics
local game = sim.new(42)
local view = { scale = 1, x = 0, y = 0 }
local screen = "title"
local elapsed, smokeFrames, captureAt, capturePath = 0, nil, nil, nil
local buttons = {}
local focusedButton
local paused = false
local loupe
local playtest = false
local playtestTime = 0
-- Analytics: the Ravensight SDK only when a release tool injected a config
-- (analytics.config.lua); otherwise nil, no toggle, nothing sent. See README.md.
local ravensight
local track
local prefs
local qaSource = "none"
local quitting = false
local MAILBOX = "/tmp/ravensight-exit.json"
local mcpEnabled = false
for _, v in ipairs(arg or {}) do
  if v == "--mcp" then
    mcpEnabled = true
  end
end
local sectors = { "THE GLASS REACH", "EMBER CORRIDOR", "THE QUIET ENGINE" }
local function updateView()
  local w, h = lg.getDimensions()
  view.scale = math.min(w / 1440, h / 900)
  view.x = (w - 1440 * view.scale) / 2
  view.y = (h - 900 * view.scale) / 2
  art.setScale(view.scale)
end
local function toWorld(x, y)
  return (x - view.x) / view.scale, (y - view.y) / view.scale
end
local function toScreen(x, y)
  return x * view.scale + view.x, y * view.scale + view.y
end
local function begin(keep, endless)
  local upgrades = keep and game.upgrades or nil
  game = sim.new(love.math.random(1, 2147483646), upgrades, 1, endless)
  backdrops.next()
  screen = "flight"
  paused = false
  track:runStarted(game)
end
local function currentSettings()
  return {
    art = art.illustrated and "illustrated" or "vector",
    reduced_motion = backdrops.reducedMotion,
    muted = audio.muted,
    music = audio.musicVolume,
    effects = audio.effectsVolume,
  }
end
local function savePrefs()
  -- Automation never rewrites the player's settings.
  if prefs and qaSource == "none" then
    prefs.save(currentSettings())
  end
end
local function buy(kind)
  local cost = sim.cost(game, kind)
  if sim.buy(game, kind) then
    track:upgradePurchased(game, kind, cost)
    return true
  end
  return false
end
local consent
local function analyticsOn()
  return consent ~= nil and consent.isOn()
end
local function toggleAnalytics()
  consent.toggle()
  track:sessionStarted(currentSettings())
end
local function writeMailbox(text)
  -- love.js keeps /tmp in its in-memory file system; the page's bridge reads
  -- it on pagehide. love.filesystem cannot write there, so plain io is used.
  if text then
    local file = io.open(MAILBOX, "w")
    if file then
      file:write(text)
      file:close()
    end
  else
    os.remove(MAILBOX)
  end
end
local function startAnalytics(args)
  qaSource = analytics.qaSource(args, os.getenv)
  local config = analytics.loadConfig(love.filesystem.load)
  local sdk = {
    track = function() end,
    enabled = function()
      return false
    end,
  }
  if config and (config.ingestKey ~= "" or browserBuild) then
    ravensight = require("lib.ravensight")
    ravensight.init({
      ingestKey = config.ingestKey,
      apiUrl = config.apiUrl,
      gameVersion = version.version,
      consent = "opt_in",
      optional = true,
      distribution = config.distribution,
      transport = browserBuild and "web" or nil,
    })
    sdk = ravensight
    local optin = require("lib.ravensight.core").OPTIN_FILE
    consent = analytics.consentSwitch({
      saved = function()
        return love.filesystem.getInfo(optin) ~= nil
      end,
      set = ravensight.setTrackingEnabled,
    })
  end
  track = analytics.new({
    sdk = sdk,
    editRevision = function()
      return loupe.editRevision()
    end,
    random = love.math.random,
    clock = love.timer.getTime,
    build = version.version,
    platform = analytics.platformName(love.system.getOS()),
    distribution = config and config.distribution or "source",
    qaSource = qaSource,
    mailbox = analytics.usesMailbox(love.system.getOS()) and ravensight and writeMailbox or nil,
    encode = ravensight and require("lib.ravensight.json").encode,
  })
end
local function button(id, label, x, y, w, h, enabled)
  enabled = enabled ~= false
  local mx, my = toWorld(love.mouse.getPosition())
  local hover = mx > x and mx < x + w and my > y and my < y + h
  local active = enabled and (hover or focusedButton == id)
  lg.push("all")
  if enabled then
    -- Soft halo, drawn outside the hit area without scaling the label.
    for spread = 9, 1, -2 do
      lg.setColor(0.40, 0.94, 0.80, (active and 0.035 or 0.018))
      lg.rectangle(
        "fill",
        x - spread,
        y - spread,
        w + spread * 2,
        h + spread * 2,
        9 + spread,
        9 + spread
      )
    end
    lg.setColor(active and 0.86 or 0.73, active and 1 or 0.98, active and 0.91 or 0.84)
  else
    lg.setColor(0.10, 0.18, 0.19)
  end
  lg.rectangle("fill", x, y, w, h, 9, 9)
  lg.setLineWidth(1)
  lg.setColor(0.47, 0.96, 0.86, enabled and 0.85 or 0.20)
  lg.rectangle("line", x, y, w, h, 9, 9)
  if focusedButton == id and enabled then
    lg.setColor(0.9, 1, 0.96)
    lg.setLineWidth(2)
    lg.rectangle("line", x - 4, y - 4, w + 8, h + 8, 12, 12)
  end
  art.font(16, true)
  local font = lg.getFont()
  if enabled then
    lg.setColor(0.03, 0.17, 0.17)
  else
    art.color("muted")
  end
  lg.print(label, x + (w - font:getWidth(label)) / 2, y + (h - font:getHeight()) / 2)
  lg.pop()
  buttons[#buttons + 1] = { id = id, x = x, y = y, w = w, h = h, enabled = enabled }
end
function love.load(args)
  art.preload()
  audio.load()
  backdrops.load()
  updateView()
  startAnalytics(args)
  prefs = settings.new({
    read = function(name)
      return love.filesystem.getInfo(name) and love.filesystem.read(name) or nil
    end,
    write = love.filesystem.write,
  })
  if qaSource == "none" then
    local saved = prefs.load()
    art.illustrated = saved.art == "illustrated"
    backdrops.reducedMotion = saved.reduced_motion
    audio.setVolume("music", saved.music)
    audio.setVolume("effects", saved.effects)
    audio.setMuted(saved.muted)
  end
  track:sessionStarted(currentSettings())
  for i, v in ipairs(args) do
    if v == "--smoke" then
      smokeFrames = tonumber(args[i + 1]) or 120
      begin(false)
    end
    if v == "--capture" then
      capturePath = args[i + 1]
      captureAt = 150
      begin(false)
    end
    if v == "--playtest" then
      playtest = true
      game = sim.new(42)
      screen = "flight"
      track:runStarted(game)
    end
    if v == "--flight" then
      begin(false)
    end
    if v == "--boss" then
      game = sim.new(42, nil, 3)
      screen = "flight"
      game.player.y = 520
      track:runStarted(game)
    end
    if v == "--title-capture" then
      screen = "title"
      capturePath = args[i + 1]
      captureAt = 2
    end
  end
end
function love.resize()
  updateView()
end
function love.update(dt)
  elapsed = elapsed + dt
  track:update(dt, screen == "flight" and not paused, screen == "dock")
  audio.update(dt, screen, game.pattern)
  backdrops.update(dt, game.sector)
  if smokeFrames then
    smokeFrames = smokeFrames - 1
    if smokeFrames <= 0 then
      love.event.quit(0)
    end
  end
  if screen == "flight" and not paused then
    local dx, dy = 0, 0
    if not loupe.isOpen() then
      dx = (love.keyboard.isDown("d", "right") and 1 or 0)
        - (love.keyboard.isDown("a", "left") and 1 or 0)
      dy = (love.keyboard.isDown("s", "down") and 1 or 0)
        - (love.keyboard.isDown("w", "up") and 1 or 0)
    end
    if playtest then
      playtestTime = playtestTime + dt
      assert(playtestTime < 180, "rendered playtest timed out")
      local target = game.enemies[1]
      for _, enemy in ipairs(game.enemies) do
        if enemy.kind == "boss" then
          target = enemy
        end
      end
      local tx, ty = 542, 550
      if target then
        tx, ty = target.x, math.max(340, math.min(690, target.y + 235))
      end
      dx, dy = (tx - game.player.x) / 100, (ty - game.player.y) / 100
      for _, enemy in ipairs(game.enemies) do
        local x, y = game.player.x - enemy.x, game.player.y - enemy.y
        local distance = math.sqrt(x * x + y * y)
        if distance < 150 then
          dx, dy = dx + x / math.max(10, distance) * 3, dy + y / math.max(10, distance) * 3
        end
      end
      for _, bullet in ipairs(game.hostile) do
        local x, y = game.player.x - bullet.x, game.player.y - bullet.y
        local distance = math.sqrt(x * x + y * y)
        if distance < 120 then
          dx = dx + x / math.max(15, distance) * 2
        end
      end
      dx, dy = math.max(-1, math.min(1, dx)), math.max(-1, math.min(1, dy))
      if #game.hostile > 6 then
        sim.pulse(game)
      end
      art.illustrated = math.floor(playtestTime / 8) % 2 == 0
    end
    sim.update(game, dt, { x = dx, y = dy })
    for _, event in ipairs(game.events) do
      audio.play(event)
    end
    if game.state == "dock" then
      screen = "dock"
    elseif game.state == "lost" then
      screen = "lost"
    elseif game.state == "victory" then
      screen = "victory"
    end
    track:observe(game)
  end
  if screen == "lost" then
    -- Let the final hit flash, shake and particles expire after combat stops.
    sim.update(game, dt, {})
  end
  if playtest and screen == "dock" then
    print("PLAYTEST sector " .. game.sector .. " cleared; kills=" .. game.kills)
    while buy("power") do
    end
    buy("repair")
    game = sim.advance(game)
    track:sectorStarted(game)
    screen = "flight"
  elseif playtest and screen == "victory" then
    print("PASS: rendered story, upgrades, boss, both art modes, music and effects")
    love.event.quit(0)
  elseif playtest and screen == "lost" then
    error("rendered playtest pilot died")
  end
  if captureAt then
    captureAt = captureAt - 1
    if captureAt == 0 then
      lg.captureScreenshot(function(data)
        local file = assert(io.open(capturePath, "wb"))
        file:write(data:encode("png"):getString())
        file:close()
        love.event.quit(0)
      end)
      captureAt = nil
    end
  end
end
local function hud()
  art.logo(35, -29, 440)
  art.text(string.format("%02d", game.sector), 1090, 26, 36, "cyan")
  art.text(sectors[game.pattern], 1152, 34, 15)
  art.text(
    game.endless and ("ENDLESS / CYCLE " .. (game.cycle + 1)) or "THREE SECTORS  /  ONE SMALL SHIP",
    1152,
    59,
    10,
    "muted"
  )
  art.line(42, 104, 1398, 104, "muted", 0.35)
  art.text(
    "FLIGHT WINDOW / " .. (art.illustrated and backdrops.name or "VECTOR SPACE"),
    42,
    112,
    10,
    "muted"
  )
  art.text("AUTO-TARGET ONLINE", 866, 112, 10, "cyan")
  art.panel(1064, 130, 334, 220)
  art.text("VESSEL  /  KESTREL", 1084, 150, 11, "muted")
  art.ship(1347, 187, 0.8, 0, elapsed)
  art.text(string.format("%02d", math.ceil(game.player.hp)), 1084, 177, 42)
  art.text("/ 40 HULL", 1150, 199, 13, "muted")
  lg.setColor(0.12, 0.18, 0.21)
  lg.rectangle("fill", 1084, 238, 294, 5)
  art.color(game.player.hp < 16 and "orange" or "cyan")
  lg.rectangle("fill", 1084, 238, 294 * game.player.hp / 40, 5)
  art.text("SALVAGE", 1084, 267, 11, "muted")
  art.text(string.format("%02d", game.gems), 1084, 286, 27, "cyan")
  art.text("LEVEL", 1230, 267, 11, "muted")
  art.text(string.format("%02d", game.level), 1230, 286, 27)
  art.panel(1064, 366, 334, 212)
  art.text("MISSION CLOCK", 1084, 385, 11, "muted")
  art.text(
    string.format("00:%02d", math.max(0, math.ceil(game.duration - game.time))),
    1084,
    412,
    39
  )
  art.text(
    game.pattern == 3 and "DESTROY THE QUIET ENGINE" or "SURVIVE THE SECTOR",
    1084,
    465,
    11,
    "cyan"
  )
  lg.setColor(0.12, 0.18, 0.21)
  lg.rectangle("fill", 1084, 493, 294, 4)
  art.color("cyan")
  lg.rectangle("fill", 1084, 493, 294 * math.min(1, game.time / game.duration), 4)
  art.text(
    string.format("%02d / %02d contacts arrived", game.spawned, #game.spawnQueue),
    1084,
    519,
    12,
    "muted"
  )
  art.text(string.format("%02d neutralized", game.kills), 1084, 544, 12)
  art.panel(1064, 594, 334, 216)
  local stats = sim.stats(game)
  art.text("SHIP STATS / LIVE", 1084, 612, 11, "muted")
  local rows = {
    { "DAMAGE / BEAM", string.format("%.1f", stats.damage), "power" },
    { "BEAMS / VOLLEY", tostring(stats.beams), "lasers" },
    { "MAX DPS", string.format("%.1f", stats.dps), "power" },
    { "SPEED", string.format("%.0f", stats.speed), "drive" },
    { "PICKUP RADIUS", string.format("%.0f", stats.magnet), "magnet" },
  }
  for i, row in ipairs(rows) do
    local y = 635 + (i - 1) * 30
    local changed = screen == "dock"
      and game.purchase
      and (game.purchase.kind == row[3] or (i == 3 and game.purchase.kind == "lasers"))
    if changed then
      lg.setColor(0.08, 0.23, 0.22)
      lg.rectangle("fill", 1078, y - 3, 304, 27, 4, 4)
    end
    art.text(row[1], 1084, y, 11, "muted")
    art.text(row[2], 1304, y, 16, changed and "cyan" or "white")
  end
  art.line(42, 837, 1398, 837, "muted", 0.35)
  art.text("KESTREL / PULSE ARRAY", 42, 856, 11, "muted")
  art.text(
    string.format("AUTO-AIM  ·  %.1f DMG  ·  %.0f RANGE", game.player.damage, game.player.range),
    350,
    856,
    11,
    "muted"
  )
  art.text(mcpEnabled and "LOUPE / MCP" or "LÖVE + LOUPE", 1150, 856, 10, "cyan")
  art.text(audio.muted and "SOUND OFF" or "SOUND ON", 1310, 856, 10, "muted")
  art.text(
    string.format(
      "MUSIC %d%% [ / ]  ·  FX %d%% - / =",
      math.floor(audio.musicVolume * 100 + 0.5),
      math.floor(audio.effectsVolume * 100 + 0.5)
    ),
    750,
    856,
    10,
    "cyan"
  )
  art.text(
    "WASD move · SPACE pulse · TAB pause · M mute · F1 inspect · V art · B sky · R reduce motion",
    42,
    881,
    10,
    "muted"
  )
  if game.pulseCooldown > 0 then
    art.text(string.format("PULSE %.1fs", game.pulseCooldown), 1120, 881, 10, "orange")
  end
  if game.turbo > 0 or game.split > 0 then
    art.text(
      string.format("TURBO %.1fs  /  PRISM %.1fs", game.turbo, game.split),
      650,
      881,
      10,
      "cyan"
    )
  end
end
local function field()
  local f = sim.field
  local sx, sy = toScreen(f.x, f.y)
  lg.setScissor(sx, sy, f.w * view.scale, f.h * view.scale)
  if art.illustrated then
    backdrops.draw(f, game.player)
  else
    art.background(backdrops.reducedMotion and 0 or elapsed, f)
  end
  if game.shake > 0 and screen == "flight" and not paused then
    lg.translate(math.sin(elapsed * 90) * game.shake * 7, math.cos(elapsed * 120) * game.shake * 7)
  end
  for _, v in ipairs(game.pickups) do
    if v.kind == "salvage" then
      art.color("cyan", 0.12)
      lg.circle("fill", v.x, v.y, 15)
      art.color("cyan")
      lg.polygon("fill", v.x, v.y - 7, v.x + 5, v.y, v.x, v.y + 7, v.x - 5, v.y)
    else
      art.icon(v.kind, v.x, v.y, 0.75 + math.sin(elapsed * 4) * 0.08, elapsed)
      art.text(
        v.kind == "turbo" and "TURBO" or (v.kind == "split" and "PRISM" or "REPAIR"),
        v.x - 20,
        v.y - 32,
        9,
        "white"
      )
    end
  end
  for _, e in ipairs(game.enemies) do
    art.enemy(e)
  end
  for _, b in ipairs(game.hostile) do
    art.hostileLaser(b)
  end
  if game.pulseRing > 0 then
    art.color("cyan", game.pulseRing)
    lg.setLineWidth(3)
    lg.circle("line", game.player.x, game.player.y, (0.6 - game.pulseRing) * 400)
  end
  for _, b in ipairs(game.bullets) do
    art.laser(b, elapsed)
  end
  for _, effect in ipairs(game.effects) do
    art.burst(effect)
  end

  if
    game.player.hp > 0 and (game.player.invulnerable == 0 or math.floor(elapsed * 20) % 2 == 0)
  then
    art.loadout(
      game.player,
      sim.stats(game).beams,
      game.turbo > 0,
      game.upgrades.drive,
      elapsed,
      game.upgrades
    )
  end
  for _, p in ipairs(game.particles) do
    art.color(p.color, math.min(1, p.life * 2))
    lg.circle("fill", p.x, p.y, 2)
  end
  if game.flash > 0 then
    art.color("orange", game.flash)
    lg.rectangle("fill", f.x, f.y, f.w, f.h)
  end
  if game.pattern == 3 then
    for _, e in ipairs(game.enemies) do
      if e.kind == "boss" then
        art.text("THE QUIET ENGINE", f.x + 360, f.y + 18, 14, "purple")
        lg.setColor(0.15, 0.10, 0.18)
        lg.rectangle("fill", f.x + 250, f.y + 44, 500, 5)
        art.color(e.hp < 90 and "orange" or "purple")
        lg.rectangle("fill", f.x + 250, f.y + 44, 500 * e.hp / e.maxHp, 5)
      end
    end
  end
  lg.setScissor()
  lg.setLineWidth(1)
  art.color("muted", 0.35)
  lg.rectangle("line", f.x, f.y, f.w, f.h, 3, 3)
end
-- The player's analytics switch and what it does, in one line. Shown only in
-- builds that can send (a release or web config); a source checkout has none.
local DISCLOSURE = "Sends anonymous play stats (sectors, upgrades, deaths) "
  .. "to the developer while ON."
local function analyticsToggle(x, y)
  if not ravensight then
    return
  end
  button("analytics", analyticsOn() and "ANALYTICS: ON" or "ANALYTICS: OFF", x, y, 230, 40)
  art.text(DISCLOSURE, x, y + 50, 11, "muted")
end
local function overlay()
  if screen == "flight" and not paused then
    if game.state == "clearing" then
      local t = math.min(1, game.transition)
      lg.setColor(0.02, 0.06, 0.09, 0.8 * t)
      lg.rectangle("fill", 180, 355, 720, 150, 8, 8)
      art.text(game.bossDefeated and "ENGINE SILENCED" or "SECTOR SECURED", 240, 382, 36, "cyan")
      art.text("Recovering salvage. Docking corridor is clear.", 240, 440, 16)
    elseif game.bannerTime > 0 then
      art.text(game.banner, 230, 170, 18, "cyan")
    end
    if game.time < 5 then
      art.text("KEEP MOVING. YOUR SHIP HANDLES THE SHOOTING.", 220, 760, 13, "cyan")
    end
    return
  end
  lg.setColor(0.015, 0.025, 0.04, 0.84)
  lg.rectangle("fill", 43, 131, 998, 678)
  if screen == "title" then
    art.text("A SMALL SPACE SHOOTER. AN OPEN WORKBENCH.", 145, 248, 11, "cyan")
    art.text("A little closer", 140, 288, 59)
    art.text("to the edge.", 140, 357, 59, "cyan")
    art.text("A short flight. Or a very long story. You choose.", 145, 458, 17, "muted")
    art.text("Steer with WASD or arrows. Your cannon finds the nearest target.", 145, 496, 14)
    art.text("Collect shards, upgrade at the dock, and silence the final engine.", 145, 521, 14)
    button("start", "STORY RUN", 145, 586, 260, 58)
    button("endless", "ENDLESS FLIGHT", 425, 586, 280, 58)
    art.ship(845, 401, 3.3, -0.14, elapsed)
    art.text(
      "SPACE: repulsor pulse. F1: inspect, edit, and make this game yours.",
      145,
      681,
      12,
      "muted"
    )
    analyticsToggle(145, 716)
  elseif paused then
    art.text("HOLDING PATTERN", 280, 338, 39)
    art.text("Take your time. The stars can wait.", 280, 400, 17, "muted")
    button("resume", "RESUME FLIGHT", 280, 456, 300, 55)
    button(
      "art",
      art.illustrated and "ART: ILLUSTRATED / V" or "ART: VECTOR / V",
      280,
      530,
      360,
      46
    )
    art.text(string.format("Music %d%%", math.floor(audio.musicVolume * 100 + 0.5)), 280, 610, 16)
    button("musicdown", "−", 440, 595, 50, 42)
    button("musicup", "+", 500, 595, 50, 42)
    art.text(
      string.format("Effects %d%%", math.floor(audio.effectsVolume * 100 + 0.5)),
      280,
      665,
      16
    )
    button("fxdown", "−", 440, 650, 50, 42)
    button("fxup", "+", 500, 650, 50, 42)
    analyticsToggle(280, 712)
  elseif screen == "lost" then
    art.text("SIGNAL LOST", 200, 315, 49, "orange")
    art.text("Every good pilot starts with a few bad flights.", 200, 390, 17, "muted")
    art.text(
      game.kills .. " contacts neutralized · " .. math.floor(game.time) .. " seconds survived",
      200,
      432,
      16
    )
    button("restart", "START A NEW RUN", 200, 495, 360, 58)
  elseif screen == "victory" then
    art.text("TRANSMISSION RESTORED", 155, 245, 12, "cyan")
    art.text("The stars are yours again.", 150, 290, 43)
    art.text("Three sectors cleared. One quiet engine, finally quiet.", 155, 363, 17, "muted")
    art.text(
      tostring((game.totalKills or 0) + game.kills)
        .. " contacts neutralized  /  "
        .. game.gems
        .. " salvage",
      155,
      410,
      16
    )
    art.text("Want to know how it works? Press F1.", 155, 474, 22, "cyan")
    art.text(
      "Loupe exposes the live game: inspect values, tune your ship, undo, and save.",
      155,
      518,
      13,
      "muted"
    )
    button("start", "ONE MORE FLIGHT", 155, 584, 300, 54)
    button("inspect", "OPEN LOUPE", 480, 584, 230, 54)
  elseif screen == "dock" then
    art.text(string.format("SECTOR %02d / COMPLETE", game.sector), 132, 207, 12, "cyan")
    art.text("Welcome back, pilot.", 128, 243, 43)
    art.text(
      string.format("Salvage recovered. +%d bonus. +12 hull on departure.", 10 + game.cycle * 2),
      132,
      309,
      14,
      "muted"
    )
    art.text(game.gems .. " SALVAGE AVAILABLE", 132, 353, 15, "cyan")
    if game.purchase then
      local r = game.purchase
      art.text(
        string.format("INSTALLED / %s  %g → %g", r.label, r.before, r.after),
        460,
        353,
        15,
        "cyan"
      )
    end
    local cards = {
      { "lasers", "Beam splitter", "One more laser per volley", 16, 3 },
      { "power", "Pulse amplifier", "+1 damage per projectile", 12, 999999 },
      { "drive", "Vector thrusters", "+35 movement speed", 12, 6 },
      { "magnet", "Tractor lens", "+40 pickup radius", 12, 6 },
    }
    for i, c in ipairs(cards) do
      local x = 132 + (i - 1) * 211
      c[4] = sim.cost(game, c[1])
      art.panel(x, 397, 194, 199)
      art.icon(c[1], x + 43, 437, 0.64, elapsed)
      art.text("MK " .. game.upgrades[c[1]], x + 113, 426, 11, "muted")
      art.text(c[2], x + 14, 468, 16)
      art.text(c[3], x + 14, 493, 10, "muted")
      local fields = { lasers = "lasers", power = "damage", drive = "speed", magnet = "magnet" }
      local amounts = { lasers = 1, power = 1, drive = 35, magnet = 40 }
      local value = game.player[fields[c[1]]]
      art.text(
        game.upgrades[c[1]] >= c[5] and string.format("%g / MAX", value)
          or string.format("%g → %g", value, value + amounts[c[1]]),
        x + 14,
        515,
        18,
        "cyan"
      )
      button(
        c[1],
        game.upgrades[c[1]] >= c[5] and "MAXED" or ("INSTALL / " .. c[4]),
        x + 14,
        545,
        166,
        35,
        game.gems >= c[4] and game.upgrades[c[1]] < c[5]
      )
    end
    button("next", "LAUNCH SECTOR " .. (game.sector + 1), 132, 620, 470, 54)
    button("repair", "REPAIR +20  /  8", 624, 620, 200, 54, game.gems >= 8 and game.player.hp < 40)
    art.text(
      "Upgrades apply immediately. MAX DPS assumes every beam hits; spread and range matter.",
      132,
      706,
      12,
      "muted"
    )
    art.text(
      "F1 → game → player to tune your ship. Cmd/Ctrl+Z undoes Loupe edits.",
      132,
      735,
      12,
      "muted"
    )
  end
end
function love.draw()
  if browserBuild then
    local file = io.open("/tmp/afterimage-window.txt", "r")
    if file then
      local width, height = file:read("*a"):match("^(%d+) (%d+)$")
      file:close()
      width, height = tonumber(width), tonumber(height)
      if width and height and (width ~= browserWidth or height ~= browserHeight) then
        browserWidth, browserHeight = width, height
        -- LÖVE reports logical dimensions; remember the requested backing size.
        -- Comparing the two on Retina repeatedly recreates the window every frame.
        love.window.updateMode(width, height)
        updateView()
        local input = io.open("/tmp/afterimage-input.txt", "w")
        if input then
          input:write(lg.getWidth(), " ", lg.getHeight())
          input:close()
        end
      end
    end
  end
  -- The SDK's timers run here rather than in love.update, because Loupe's
  -- clock can stop the game's update; a quit held for the last events must
  -- still finish.
  if ravensight then
    ravensight.update()
  end
  track:inspector(loupe.isOpen(), paused and "paused" or screen)
  lg.clear(0.015, 0.024, 0.033)
  if art.illustrated then
    local width, height = lg.getDimensions()
    backdrops.draw({ x = 0, y = 0, w = width, h = height }, { x = width / 2, y = height / 2 })
    lg.setColor(0.005, 0.01, 0.02, 0.85)
    lg.rectangle("fill", 0, 0, width, height)
  end
  lg.push()
  lg.translate(view.x, view.y)
  lg.scale(view.scale)
  buttons = {}
  lg.push()
  field()
  lg.pop()
  hud()
  overlay()
  if backdrops.error then
    art.text(backdrops.error, 132, 780, 13, "orange")
  end
  lg.pop()
end
local function action(id)
  focusedButton = nil
  if id == "analytics" then
    toggleAnalytics()
  elseif id == "art" then
    art.illustrated = not art.illustrated
    track:artStyleChanged(art.illustrated, "button")
  elseif id == "musicdown" then
    audio.setVolume("music", audio.musicVolume - 0.1)
  elseif id == "musicup" then
    audio.setVolume("music", audio.musicVolume + 0.1)
  elseif id == "fxdown" then
    audio.setVolume("effects", audio.effectsVolume - 0.1)
  elseif id == "fxup" then
    audio.setVolume("effects", audio.effectsVolume + 0.1)
  elseif id == "restart" then
    begin(false, game.endless)
  elseif id == "start" then
    begin(false)
  elseif id == "endless" then
    begin(false, true)
  elseif id == "resume" then
    paused = false
  elseif id == "next" then
    game = sim.advance(game)
    track:sectorStarted(game)
    screen = "flight"
    paused = false
  elseif id == "inspect" then
    loupe.setOpen(true)
  elseif id == "replay" then
    begin(true)
  elseif buy(id) then
    audio.play("buy")
  end
  savePrefs()
end
function love.mousemoved()
  focusedButton = nil
end
function love.mousepressed(x, y, b)
  if b ~= 1 then
    return
  end
  x, y = toWorld(x, y)
  for _, v in ipairs(buttons) do
    if v.enabled and x >= v.x and x <= v.x + v.w and y >= v.y and y <= v.y + v.h then
      action(v.id)
      break
    end
  end
end
function love.keypressed(key)
  if screen ~= "flight" or paused then
    if key == "left" or key == "right" or key == "up" or key == "down" then
      local choices, selected = {}, nil
      for _, item in ipairs(buttons) do
        if item.enabled then
          choices[#choices + 1] = item.id
          if item.id == focusedButton then
            selected = #choices
          end
        end
      end
      if #choices > 0 then
        local direction = (key == "left" or key == "up") and -1 or 1
        focusedButton = choices[selected and ((selected - 1 + direction) % #choices + 1) or 1]
      end
      return
    elseif key == "return" and focusedButton then
      for _, item in ipairs(buttons) do
        if item.id == focusedButton and item.enabled then
          action(item.id)
          return
        end
      end
    end
  end
  if not browserBuild then
    if key == "f11" then
      window.toggleFullscreen()
      updateView()
      return
    end
    if key == "f10" then
      window.cycleSize()
      updateView()
      return
    end
  end
  if key == "return" or key == "space" then
    if screen == "lost" then
      begin(false, game.endless)
    elseif screen == "title" or screen == "victory" then
      begin(false)
    elseif screen == "dock" then
      action("next")
    elseif screen == "flight" and not paused and key == "space" then
      if sim.pulse(game) then
        audio.play("level")
      end
    end
  elseif key == "tab" and screen == "flight" then
    paused = not paused
  elseif key == "v" then
    art.illustrated = not art.illustrated
    track:artStyleChanged(art.illustrated, "key")
  elseif key == "b" then
    backdrops.next()
  elseif key == "r" then
    backdrops.reducedMotion = not backdrops.reducedMotion
  elseif key == "[" then
    audio.setVolume("music", audio.musicVolume - 0.1)
  elseif key == "]" then
    audio.setVolume("music", audio.musicVolume + 0.1)
  elseif key == "-" then
    audio.setVolume("effects", audio.effectsVolume - 0.1)
  elseif key == "=" then
    audio.setVolume("effects", audio.effectsVolume + 0.1)
  elseif key == "m" then
    audio.setMuted(not audio.muted)
  elseif key == "escape" then
    if screen == "flight" then
      paused = not paused
    else
      love.event.quit()
    end
  end
  savePrefs()
end
function love.quit()
  -- Runs again when the SDK ends a held quit; record the end only once.
  if not quitting then
    quitting = true
    track:quit(paused and "paused" or screen)
  end
  if ravensight then
    return ravensight.quit()
  end
  return false
end
function love.filedropped(file)
  backdrops.import(file)
end
loupe = require("loupe")
loupe.watch(function()
  return game
end, "game")
loupe.watch(art, "art")
loupe.watch(audio, "sound")
loupe.watch(backdrops, "backdrops")
loupe.attach({
  toWorld = toWorld,
  toScreen = toScreen,
  center = true,
  hotReload = false,
  mcp = mcpEnabled,
})
