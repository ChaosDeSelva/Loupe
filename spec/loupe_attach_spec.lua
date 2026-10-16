local love_stub = require("spec.support.love_stub")
local ui_driver = require("spec.support.ui_driver")

describe("loupe.attach", function()
  local loupe, fake, gameCalls

  local function defineGame()
    gameCalls = {}
    love.update = function(dt)
      gameCalls[#gameCalls + 1] = { "update", dt }
    end
    love.draw = function()
      gameCalls[#gameCalls + 1] = { "draw" }
    end
    love.keypressed = function(key)
      gameCalls[#gameCalls + 1] = { "keypressed", key }
    end
  end

  -- Where loupe drew a widget last frame (see ui_driver.at), so clicks
  -- follow the layout instead of hard-coded pixels.
  local function at(key, dx, dy)
    return ui_driver.at(loupe._debugUi(), key, dx, dy)
  end

  -- Clicks a loupe widget through the game's callbacks, then draws a frame.
  local function clickOn(key, dx, dy)
    local x, y = at(key, dx, dy)
    love.mousepressed(x, y, 1)
    love.mousereleased(x, y, 1)
    love.draw()
  end

  local function drewText(pattern)
    for _, call in ipairs(fake.calls) do
      if call[1] == "print" and tostring(call[2]):find(pattern) then
        return true
      end
    end
    return false
  end

  -- Saves and reloads print to the console; keep busted's output clean.
  -- Blocks that check what was printed stub print again on top of this.
  local quiet

  before_each(function()
    quiet = stub(_G, "print")
    package.loaded["loupe"] = nil
    loupe = require("loupe")
    fake = love_stub.install()
    defineGame()
  end)

  after_each(function()
    loupe.detach()
    love_stub.uninstall()
    quiet:revert()
  end)

  it("does nothing when graphics is unavailable (headless runs)", function()
    love_stub.install({ graphics = false })
    defineGame()
    loupe.attach()
    assert.is_false(loupe.isAttached())
    assert.is_nil(getmetatable(love))
  end)

  it("leaves the game untouched while closed and running", function()
    loupe.attach()
    love.update(0.016)
    love.draw()
    love.keypressed("p")
    assert.same({ { "update", 0.016 }, { "draw" }, { "keypressed", "p" } }, gameCalls)
    assert.same({}, fake.calls)
  end)

  it("toggles the overlay with F1 without forwarding it to the game", function()
    loupe.attach()
    love.keypressed("f1")
    assert.is_true(loupe.isOpen())
    love.keypressed("f1")
    assert.is_false(loupe.isOpen())
    assert.same({}, gameCalls)
  end)

  it("draws the status bar over the game while open", function()
    loupe.attach({ open = true })
    love.draw()
    assert.same({ "draw" }, gameCalls[1])
    assert.is_true(drewText("RUNNING"))
  end)

  describe("time controls (overlay open)", function()
    before_each(function()
      loupe.attach({ open = true })
    end)

    it("pauses the game's update and consumes the key", function()
      love.keypressed("p")
      love.update(0.016)
      assert.same({}, gameCalls)
    end)

    it("steps one fixed frame", function()
      love.keypressed(".")
      love.update(0.5)
      love.update(0.5)
      assert.same({ { "update", 1 / 60 } }, gameCalls)
    end)

    it("changes and resets speed", function()
      love.keypressed("]")
      love.update(0.01)
      love.keypressed("1")
      love.update(0.01)
      assert.same({ { "update", 0.02 }, { "update", 0.01 } }, gameCalls)
    end)

    it("forwards keys it doesn't use", function()
      love.keypressed("space")
      assert.same({ { "keypressed", "space" } }, gameCalls)
    end)
  end)

  it("ignores its time keys while closed", function()
    loupe.attach()
    love.keypressed("p")
    love.update(0.016)
    assert.same({ { "keypressed", "p" }, { "update", 0.016 } }, gameCalls)
  end)

  it("keeps a small badge on screen when closed but paused", function()
    loupe.attach({ open = true })
    love.keypressed("p")
    love.keypressed("f1")
    love.draw()
    assert.is_true(drewText("PAUSED"))
  end)

  describe("mouse routing (overlay open)", function()
    -- The top bar's Pause button, found after the first frame.
    local PAUSE_X, PAUSE_Y

    before_each(function()
      love.mousepressed = function(x, y, button)
        gameCalls[#gameCalls + 1] = { "mousepressed", x, y, button }
      end
      love.mousereleased = function(x, y, button)
        gameCalls[#gameCalls + 1] = { "mousereleased", x, y, button }
      end
      love.wheelmoved = function(dx, dy)
        gameCalls[#gameCalls + 1] = { "wheelmoved", dx, dy }
      end
      -- These tests are about loupe's windows; world picking has its own block.
      loupe.attach({ open = true, pick = false })
      love.draw() -- first frame: the toolbar window now exists for hit-testing
      PAUSE_X, PAUSE_Y = at("loupe.toolbar/pause")
      gameCalls = {}
    end)

    it("clicks loupe's buttons without the game seeing the click", function()
      love.mousepressed(PAUSE_X, PAUSE_Y, 1)
      love.mousereleased(PAUSE_X, PAUSE_Y, 1)
      love.draw()
      love.update(0.016)
      assert.same({ { "draw" } }, gameCalls) -- no mouse events, no update: paused
    end)

    it("passes clicks outside loupe's windows to the game", function()
      love.mousepressed(600, 400, 1)
      love.mousereleased(600, 400, 1)
      assert.same({ { "mousepressed", 600, 400, 1 }, { "mousereleased", 600, 400, 1 } }, gameCalls)
    end)

    it("keeps a release that ends a loupe drag away from the game", function()
      love.mousepressed(PAUSE_X, PAUSE_Y, 1)
      love.mousereleased(600, 400, 1)
      assert.same({}, gameCalls)
    end)

    it("keeps wheel events over a window", function()
      love.mousemoved(PAUSE_X, PAUSE_Y)
      love.wheelmoved(0, 1)
      love.mousemoved(600, 400)
      love.wheelmoved(0, 1)
      assert.same({ { "wheelmoved", 0, 1 } }, gameCalls)
    end)

    it("gives everything back to the game once closed", function()
      love.keypressed("f1")
      love.mousepressed(PAUSE_X, PAUSE_Y, 1)
      assert.same({ { "mousepressed", PAUSE_X, PAUSE_Y, 1 } }, gameCalls)
    end)
  end)

  describe("world picking (overlay open)", function()
    local crate
    before_each(function()
      love.mousepressed = function(x, y, button)
        gameCalls[#gameCalls + 1] = { "mousepressed", x, y, button }
      end
      crate = { x = 600, y = 400, w = 20, h = 20 }
      loupe.watch({ crate = crate }, "level")
    end)

    it("selects and drags objects, keeping the clicks from the game", function()
      loupe.attach({ open = true })
      love.draw()
      gameCalls = {}

      love.mousepressed(610, 410, 1)
      love.draw()
      assert.is_true(drewText("level.crate"))
      love.mousemoved(630, 425)
      love.draw()
      love.mousereleased(630, 425, 1)
      love.draw()
      assert.same({ 620, 415 }, { crate.x, crate.y })
      assert.same({ { "draw" }, { "draw" }, { "draw" } }, gameCalls)
    end)

    it("uses the game's view transform", function()
      loupe.attach({
        open = true,
        toWorld = function(sx, sy)
          return sx / 2, sy / 2
        end,
        toScreen = function(wx, wy)
          return wx * 2, wy * 2
        end,
      })
      love.draw()
      love.mousepressed(1220, 820, 1) -- world (610, 410)
      love.draw()
      love.mousemoved(1240, 820) -- +20 screen = +10 world
      love.draw()
      assert.equal(610, crate.x)
    end)

    it("can be switched off from the toolbar, giving clicks back to the game", function()
      loupe.attach({ open = true })
      love.draw()
      clickOn("loupe.toolbar/pick")
      gameCalls = {}
      love.mousepressed(610, 410, 1)
      assert.same({ { "mousepressed", 610, 410, 1 } }, gameCalls)
    end)

    it("can start switched off", function()
      loupe.attach({ open = true, pick = false })
      love.draw()
      gameCalls = {}
      love.mousepressed(610, 410, 1)
      assert.same({ { "mousepressed", 610, 410, 1 } }, gameCalls)
    end)
  end)

  describe("undo, redo and save (overlay open)", function()
    local crate

    local function drag()
      love.mousepressed(610, 410, 1)
      love.draw()
      love.mousemoved(630, 420)
      love.draw()
      love.mousereleased(630, 420, 1)
      love.draw()
    end

    before_each(function()
      crate = { x = 600, y = 400, w = 20, h = 20 }
      loupe.watch({ crate = crate }, "level")
      loupe.attach({ open = true })
      love.draw()
      gameCalls = {}
    end)

    it("undoes a whole drag with ctrl+z and redoes it with ctrl+shift+z", function()
      drag()
      assert.same({ 620, 410 }, { crate.x, crate.y })
      fake.keysDown.lctrl = true
      love.keypressed("z")
      assert.same({ 600, 400 }, { crate.x, crate.y })
      fake.keysDown.lshift = true
      love.keypressed("z")
      assert.same({ 620, 410 }, { crate.x, crate.y })
    end)

    it("redoes with ctrl+y, and treats cmd like ctrl", function()
      drag()
      fake.keysDown.lgui = true
      love.keypressed("z")
      assert.equal(600, crate.x)
      love.keypressed("y")
      assert.equal(620, crate.x)
    end)

    it("has Undo and Redo buttons in the toolbar", function()
      drag()
      clickOn("loupe.toolbar/Undo")
      assert.equal(600, crate.x)
      clickOn("loupe.toolbar/Redo")
      assert.equal(620, crate.x)
    end)

    it("leaves z to the game without ctrl, or when the overlay is closed", function()
      love.keypressed("z")
      love.keypressed("f1")
      fake.keysDown.lctrl = true
      love.keypressed("z")
      assert.same({ { "keypressed", "z" }, { "keypressed", "z" } }, gameCalls)
    end)

    it("saves overrides with ctrl+s, showing unsaved state until then", function()
      drag()
      assert.is_true(drewText("unsaved"))
      fake.keysDown.lctrl = true
      love.keypressed("s")
      local file = fake.files["loupe_overrides.lua"]
      assert.truthy(file:find('{ "level", { "crate", "x" }, 620 }', 1, true))
      -- Clear in place: the stub records into this exact table.
      for i = #fake.calls, 1, -1 do
        fake.calls[i] = nil
      end
      love.draw()
      assert.is_true(drewText("saved 2 overrides"))
    end)

    it("saves from the toolbar's Save button", function()
      drag()
      clickOn("loupe.toolbar/Save")
      assert.truthy(fake.files["loupe_overrides.lua"])
    end)
  end)

  describe("1.0 integration", function()
    local function clearCalls()
      for i = #fake.calls, 1, -1 do
        fake.calls[i] = nil
      end
    end

    it("marks the selection stale once it's no longer at its path", function()
      local level = { crate = { x = 600, y = 400, w = 20, h = 20 } }
      loupe.watch(level, "level")
      loupe.attach({ open = true })
      love.draw()
      love.mousepressed(610, 410, 1)
      love.mousereleased(610, 410, 1)
      love.draw()
      assert.is_false(drewText("no longer in the game"))
      level.crate = nil
      love.draw()
      assert.is_true(drewText("no longer in the game"))
    end)

    it("saves Inspector edits to an object that was picked in the world", function()
      local crate = { x = 600, y = 400, w = 20, h = 20 }
      loupe.watch({ crate = crate }, "level")
      loupe.attach({ open = true })
      love.draw()
      love.mousepressed(610, 410, 1) -- pick the crate in the world
      love.mousereleased(610, 410, 1)
      love.draw()
      clickOn("loupe.inspector/x")
      love.textinput("1")
      love.keypressed("return")
      love.draw()
      assert.equal(6001, crate.x)
      fake.keysDown.lctrl = true
      love.keypressed("s")
      local file = fake.files["loupe_overrides.lua"]
      assert.truthy(file and file:find('{ "level", { "crate", "x" }, 6001 }', 1, true))
    end)

    it("shows unsaved changes without hiding the latest message", function()
      local crate = { x = 600, y = 400, w = 20, h = 20 }
      loupe.watch({ crate = crate }, "level")
      loupe.attach({ open = true })
      love.draw()
      -- Each press needs its own frame before the move, as with a real mouse.
      love.mousepressed(610, 410, 1)
      love.draw()
      love.mousemoved(630, 410)
      love.draw()
      love.mousereleased(630, 410, 1)
      love.draw()
      fake.keysDown.lctrl = true
      love.keypressed("s")
      fake.keysDown.lctrl = nil
      love.mousepressed(630, 410, 1)
      love.draw()
      love.mousemoved(650, 410)
      love.draw()
      love.mousereleased(650, 410, 1)
      clearCalls()
      love.draw()
      assert.is_true(drewText("unsaved changes"))
      assert.is_true(drewText("saved 1 override"))
    end)

    it("turns key repeat on only while typing in a loupe field", function()
      local player = { name = "bob" }
      loupe.watch(player, "player")
      loupe.attach({ open = true, pick = false })
      love.draw()
      clickOn("loupe.objects/player")
      clickOn("loupe.inspector/name")
      assert.is_true(fake.keyRepeat)
      love.keypressed("return")
      love.draw()
      assert.is_false(fake.keyRepeat)
    end)

    it("restores key repeat if the overlay closes mid-edit", function()
      local player = { name = "bob" }
      loupe.watch(player, "player")
      loupe.attach({ open = true, pick = false })
      love.draw()
      clickOn("loupe.objects/player")
      clickOn("loupe.inspector/name")
      love.keypressed("f1")
      love.draw()
      assert.is_false(fake.keyRepeat)
    end)
  end)

  describe("loading overrides", function()
    local overrides = require("loupe.core.overrides")

    local function saveFile(entries)
      fake.files["loupe_overrides.lua"] = overrides.render(entries)
    end

    it("applies saved values to watched roots before the game updates", function()
      local crate = { x = 600 }
      saveFile({ { root = "level", keys = { "crate", "x" }, value = 111 } })
      loupe.watch({ crate = crate }, "level")
      love.update = function()
        gameCalls[#gameCalls + 1] = { "update", crate.x }
      end
      loupe.attach()
      love.update(0.016)
      assert.same({ { "update", 111 } }, gameCalls)
    end)

    it("re-applies them whenever a getter returns a new table", function()
      local game = { ship = { thrust = 1 } }
      saveFile({ { root = "game", keys = { "ship", "thrust" }, value = 9 } })
      loupe.watch(function()
        return game
      end, "game")
      loupe.attach()
      love.update(0.016)
      assert.equal(9, game.ship.thrust)
      game = { ship = { thrust = 1 } } -- the game restarts
      love.update(0.016)
      assert.equal(9, game.ship.thrust)
    end)

    it("reports overrides that no longer match the game", function()
      saveFile({ { root = "level", keys = { "gone", "x" }, value = 1 } })
      loupe.watch({}, "level")
      loupe.attach({ open = true })
      love.update(0.016)
      love.draw()
      assert.is_true(drewText("1 saved override no longer matches"))
    end)

    it("reports an overrides file it can't read", function()
      fake.files["loupe_overrides.lua"] = "return {"
      loupe.attach({ open = true })
      love.draw()
      assert.is_true(drewText("couldn't read"))
    end)
  end)

  describe("hot reload", function()
    local ship, printStub

    local function speed()
      return 1
    end

    local function edit(path, source)
      fake.files[path] = source
      fake.modtimes[path] = (fake.modtimes[path] or 1) + 1
    end

    local function addModule(name, path, value)
      fake.files[path] = "return {}"
      fake.modtimes[path] = 1
      package.loaded[name] = value
      return value
    end

    before_each(function()
      ship = addModule("t_game.ship", "t_game/ship.lua", { speed = speed })
      printStub = stub(_G, "print")
    end)

    after_each(function()
      printStub:revert()
      package.loaded["t_game.ship"] = nil
      package.loaded["t_game.rock"] = nil
    end)

    it("patches an edited module and says so", function()
      loupe.attach({ open = true, hotReload = true })
      edit("t_game/ship.lua", "return { speed = function() return 2 end }")
      love.update(0.5)
      love.draw()
      assert.equal(2, ship.speed())
      assert.is_true(drewText("reloaded t_game.ship"))
      assert.stub(printStub).was.called_with("loupe: reloaded t_game.ship")
    end)

    it("counts several modules reloaded at once", function()
      addModule("t_game.rock", "t_game/rock.lua", {})
      loupe.attach({ open = true, hotReload = true })
      edit("t_game/ship.lua", "return {}")
      edit("t_game/rock.lua", "return {}")
      love.update(0.5)
      love.draw()
      assert.is_true(drewText("reloaded 2 modules"))
    end)

    it("keeps the old code and warns when a reload fails", function()
      loupe.attach({ open = true, hotReload = true })
      edit("t_game/ship.lua", "error('typo')")
      love.update(0.5)
      love.draw()
      assert.equal(speed, ship.speed)
      assert.is_true(drewText("reload failed: t_game.ship: "))
      assert.stub(printStub).was.called()
      local printed = printStub.calls[1].refs[1]
      assert.truthy(printed:find("loupe: reload failed: t_game.ship: ", 1, true))
      assert.truthy(printed:find("typo", 1, true))
    end)

    it("reports a failure over successes in the same check", function()
      addModule("t_game.rock", "t_game/rock.lua", {})
      loupe.attach({ open = true, hotReload = true })
      edit("t_game/ship.lua", "error('typo')")
      edit("t_game/rock.lua", "return {}")
      love.update(0.5)
      love.draw()
      assert.is_true(drewText("reload failed: t_game.ship"))
    end)

    it("shows a failed reload in the corner badge while the overlay is closed", function()
      loupe.attach({ hotReload = true })
      edit("t_game/ship.lua", "error('typo')")
      love.update(0.5)
      love.draw()
      assert.is_true(drewText("reload failed"))
      -- Opening the overlay acknowledges it; closed again, the badge is gone.
      love.keypressed("f1")
      love.keypressed("f1")
      for i = #fake.calls, 1, -1 do
        fake.calls[i] = nil
      end
      love.draw()
      assert.is_false(drewText("reload failed"))
    end)

    it("checks at most every half second, even while paused", function()
      loupe.attach({ hotReload = true })
      love.keypressed("f1")
      love.keypressed("p")
      edit("t_game/ship.lua", "return { speed = function() return 2 end }")
      love.update(0.2)
      love.update(0.2)
      assert.equal(speed, ship.speed)
      love.update(0.2)
      assert.equal(2, ship.speed())
      assert.same({}, gameCalls) -- still paused
    end)

    it("skips modules matching reloadIgnore", function()
      loupe.attach({ hotReload = true, reloadIgnore = { "^t_game%." } })
      edit("t_game/ship.lua", "return { speed = function() return 2 end }")
      love.update(1)
      assert.equal(speed, ship.speed)
    end)

    it("can be turned off", function()
      loupe.attach({ hotReload = false })
      edit("t_game/ship.lua", "return { speed = function() return 2 end }")
      love.update(1)
      assert.equal(speed, ship.speed)
    end)

    it("is off by default unless the game runs from a folder", function()
      loupe.attach()
      edit("t_game/ship.lua", "return { speed = function() return 2 end }")
      love.update(1)
      assert.equal(speed, ship.speed)
    end)

    it("is on by default when the game runs from a folder", function()
      local folder = os.tmpname()
      os.remove(folder)
      assert(os.execute(('mkdir "%s"'):format(folder)))
      local main = assert(io.open(folder .. "/main.lua", "w"))
      main:close()
      fake.source = folder
      finally(function()
        os.remove(folder .. "/main.lua")
        os.remove(folder)
      end)

      loupe.attach()
      edit("t_game/ship.lua", "return { speed = function() return 2 end }")
      love.update(1)
      assert.equal(2, ship.speed())
    end)

    it("never runs when attach did nothing (headless)", function()
      fake = love_stub.install({ graphics = false })
      fake.files["t_game/ship.lua"] = "return {}"
      fake.modtimes["t_game/ship.lua"] = 1
      defineGame()
      loupe.attach({ hotReload = true })
      edit("t_game/ship.lua", "return { speed = function() return 2 end }")
      love.update(1)
      assert.equal(speed, ship.speed)
    end)
  end)

  describe("watch", function()
    it("can be called before attach and while headless", function()
      love_stub.install({ graphics = false })
      assert.has_no.errors(function()
        loupe.watch({}, "early")
      end)
    end)

    it("returns the watched target for chaining", function()
      local t = {}
      assert.equal(t, loupe.watch(t, "t"))
    end)

    it("edits a watched table end to end; typing never triggers time hotkeys", function()
      local player = { name = "bob" }
      loupe.watch(player, "player")
      loupe.attach({ open = true })
      love.keypressed("]") -- speed x2 before we start typing
      love.draw()

      clickOn("loupe.objects/player")
      clickOn("loupe.inspector/name")

      love.textinput("1")
      love.keypressed("1") -- would reset speed if hotkeys were live
      love.keypressed("return")
      love.draw()
      assert.equal("bob1", player.name)

      gameCalls = {}
      love.update(0.01)
      assert.same({ { "update", 0.02 } }, gameCalls)
    end)

    it("unwatches by name", function()
      loupe.watch({}, "gone")
      loupe.unwatch("gone")
      loupe.attach({ open = true })
      love.draw()
      assert.is_true(drewText("Nothing watched"))
    end)
  end)

  describe("1.1 hardening", function()
    local function clearCalls()
      for i = #fake.calls, 1, -1 do
        fake.calls[i] = nil
      end
    end

    local function drag(fromX, fromY, toX, toY)
      love.mousepressed(fromX, fromY, 1)
      love.draw()
      love.mousemoved(toX, toY)
      love.draw()
      love.mousereleased(toX, toY, 1)
      love.draw()
    end

    -- What hump.gamestate.registerEvents() does, typically from love.load.
    local function registerEvents()
      for _, name in ipairs({ "update", "draw" }) do
        local old = love[name]
        love[name] = function(...)
          old(...)
          gameCalls[#gameCalls + 1] = { "gamestate." .. name }
        end
      end
    end

    it("survives a library chaining love callbacks after attach", function()
      loupe.attach({ open = true })
      registerEvents()
      love.update(0.016)
      love.draw()
      assert.same({
        { "update", 0.016 },
        { "gamestate.update" },
        { "draw" },
        { "gamestate.draw" },
      }, gameCalls)
      assert.is_true(drewText("RUNNING")) -- loupe still draws, once
      loupe.detach()
      gameCalls = {}
      love.update(0.016)
      assert.same({ { "update", 0.016 }, { "gamestate.update" } }, gameCalls)
    end)

    it("edits a field reached through a function key but says it can't save it", function()
      local crate = { x = 600, y = 400, w = 20, h = 20 }
      local handle = function() end
      loupe.watch({ [handle] = crate }, "level")
      loupe.attach({ open = true })
      love.draw()
      drag(610, 410, 630, 410)
      assert.equal(620, crate.x)
      clearCalls()
      love.draw()
      assert.is_true(drewText("can't save level%[function"))
      fake.keysDown.lctrl = true
      love.keypressed("z")
      assert.equal(600, crate.x)
    end)

    it("says the same for boolean keys", function()
      local crate = { x = 600, y = 400, w = 20, h = 20 }
      loupe.watch({ [true] = crate }, "level")
      loupe.attach({ open = true })
      love.draw()
      drag(610, 410, 630, 410)
      clearCalls()
      love.draw()
      assert.is_true(drewText("can't save level%[true%]"))
    end)

    it("undoes on the current table after a getter's root was replaced", function()
      local level = { crate = { x = 600, y = 400, w = 20, h = 20 } }
      loupe.watch(function()
        return level
      end, "level")
      loupe.attach({ open = true })
      love.draw()
      drag(610, 410, 630, 410)
      level = { crate = { x = 620, y = 400, w = 20, h = 20 } } -- restarted, override re-applied
      fake.keysDown.lctrl = true
      love.keypressed("z")
      assert.equal(600, level.crate.x)
    end)

    it("saves, undoes and redoes with ctrl/cmd while a loupe field has focus", function()
      local player = { name = "bob", hp = 1 }
      loupe.watch(player, "player")
      loupe.attach({ open = true, pick = false })
      love.draw()
      clickOn("loupe.objects/player")
      clickOn("loupe.inspector/hp")
      love.textinput("2")
      love.keypressed("return")
      love.draw()
      assert.equal(12, player.hp)
      clickOn("loupe.inspector/name")
      love.textinput("x")
      fake.keysDown.lctrl = true
      love.keypressed("s")
      local file = fake.files["loupe_overrides.lua"]
      assert.truthy(file and file:find('{ "player", { "hp" }, 12 }', 1, true))
      assert.falsy(file:find("bobx", 1, true)) -- the field isn't committed by saving
      love.keypressed("z")
      assert.equal(1, player.hp)
      love.keypressed("y")
      assert.equal(12, player.hp)
      fake.keysDown.lctrl = nil
      love.keypressed("return")
      love.draw() -- the field commits while it's built
      assert.equal("bobx", player.name) -- the field kept its text
    end)

    describe("error boundary", function()
      local printStub
      before_each(function()
        printStub = stub(_G, "print")
      end)
      after_each(function()
        printStub:revert()
      end)

      local function printedError(pattern)
        for _, call in ipairs(printStub.calls) do
          local text = tostring(call.refs[1])
          if text:find("^loupe: ") and text:find(pattern, 1, true) and text:find("traceback") then
            return true
          end
        end
        return false
      end

      -- The game keeps running and loupe closes, saying why.
      local function assertRecovered(pattern)
        assert.is_false(loupe.isOpen())
        assert.is_true(printedError(pattern))
        clearCalls()
        love.draw()
        assert.is_true(drewText("Loupe hit an error"))
        love.keypressed("f1")
        assert.is_true(loupe.isOpen())
      end

      it("catches a throwing bounds hook", function()
        loupe.watch({ crate = { x = 1, y = 1 } }, "level")
        loupe.attach({
          open = true,
          bounds = function()
            error("bounds hook broke")
          end,
        })
        assert.has_no.errors(function()
          love.draw()
        end)
        assert.same({ { "draw" } }, gameCalls)
        assertRecovered("bounds hook broke")
      end)

      it("catches a throwing toWorld hook", function()
        loupe.attach({
          open = true,
          toWorld = function()
            error("camera broke")
          end,
        })
        assert.has_no.errors(function()
          love.mousemoved(10, 10)
          love.draw()
          love.draw()
        end)
        assertRecovered("camera broke")
      end)

      it("catches a strict table refusing a drag", function()
        local data = { x = 600, y = 400, w = 20, h = 20 }
        local crate = setmetatable({}, {
          __index = data,
          __newindex = function()
            error("crate is read-only")
          end,
        })
        loupe.watch({ crate = crate }, "level")
        loupe.attach({ open = true })
        love.draw()
        assert.has_no.errors(function()
          drag(610, 410, 630, 410)
        end)
        assertRecovered("crate is read-only")
      end)

      it("catches a strict table that throws on unknown fields", function()
        local strict = setmetatable({}, {
          __index = function(_, k)
            error("no field " .. tostring(k))
          end,
        })
        loupe.watch({ strict = strict }, "level")
        loupe.attach({ open = true })
        assert.has_no.errors(function()
          love.draw()
        end)
        assertRecovered("no field")
      end)

      it("shows keys whose __tostring throws", function()
        local function badKey()
          return setmetatable({}, {
            __tostring = function()
              error("tostring broke")
            end,
          })
        end
        loupe.watch({ [badKey()] = {}, [badKey()] = {} }, "level")
        loupe.attach({ open = true })
        assert.has_no.errors(function()
          love.draw()
        end)
        assert.is_true(loupe.isOpen()) -- handled, not just caught
      end)

      it("copes with NaN boxes from a bounds hook", function()
        loupe.watch({ a = {}, b = {} }, "level")
        loupe.attach({
          open = true,
          bounds = function()
            return 0 / 0, 0 / 0, 0 / 0, 0 / 0
          end,
        })
        assert.has_no.errors(function()
          love.mousemoved(10, 10)
          love.draw()
          love.mousepressed(10, 10, 1)
          love.draw()
        end)
        assert.is_true(loupe.isOpen())
      end)

      it("catches errors applying saved overrides, and the game still updates", function()
        fake.files["loupe_overrides.lua"] = 'return { { "level", { "crate", "x" }, 5 } }'
        local crate = setmetatable({}, {
          __index = { x = 1 },
          __newindex = function()
            error("crate is read-only")
          end,
        })
        loupe.watch({ crate = crate }, "level")
        loupe.attach({ open = true })
        assert.has_no.errors(function()
          love.update(0.016)
        end)
        assert.same({ { "update", 0.016 } }, gameCalls)
        assertRecovered("crate is read-only")
        printStub:clear()
        love.update(0.016) -- doesn't retry the same table every frame
        assert.stub(printStub).was_not.called()
      end)

      it("works again after reopening, even if the error left a window half-built", function()
        local objects = require("loupe.panels.objects")
        local build = objects.build
        objects.build = function(c)
          objects.build = build -- fail once
          c:beginWindow("broken", "Broken", { x = 0, y = 0, w = 10, h = 10 })
          error("panel broke")
        end
        loupe.attach({ open = true, pick = false })
        assert.has_no.errors(function()
          love.draw()
        end)
        objects.build = build
        assertRecovered("panel broke")
        printStub:clear()
        clearCalls()
        love.draw()
        assert.stub(printStub).was_not.called()
        assert.is_true(loupe.isOpen())
        assert.is_true(drewText("RUNNING"))
      end)

      it("reports an error once, not every frame, until reopened", function()
        loupe.attach({
          open = true,
          toWorld = function()
            error("camera broke")
          end,
        })
        love.draw()
        love.keypressed("f1")
        love.draw()
        love.draw()
        local reports = 0
        for _, call in ipairs(printStub.calls) do
          if tostring(call.refs[1]):find("camera broke") then
            reports = reports + 1
          end
        end
        assert.equal(2, reports)
        assert.is_false(loupe.isOpen())
      end)
    end)
  end)

  describe("docked layout", function()
    local function resize(w, h)
      rawset(love.graphics, "getWidth", function()
        return w
      end)
      rawset(love.graphics, "getHeight", function()
        return h
      end)
    end

    local function rect(id)
      return loupe._debugUi():rectOf(id)
    end

    it("docks a full-width bar and a full-height sidebar", function()
      loupe.attach({ open = true })
      love.draw()
      local bar = rect("loupe.toolbar")
      local objects, inspector = rect("loupe.objects"), rect("loupe.inspector")
      assert.same({ 0, 0, 800 }, { bar.x, bar.y, bar.w })
      assert.same({ 0, bar.h }, { objects.x, objects.y })
      assert.equal(objects.y + objects.h, inspector.y)
      assert.equal(600, inspector.y + inspector.h)
    end)

    it("follows window resizes, keeping everything on screen", function()
      loupe.attach({ open = true })
      love.draw()
      resize(1600, 900)
      love.draw()
      assert.equal(1600, rect("loupe.toolbar").w)
      local inspector = rect("loupe.inspector")
      assert.equal(900, inspector.y + inspector.h)
      resize(640, 360)
      love.draw()
      for _, id in ipairs({ "loupe.toolbar", "loupe.objects", "loupe.inspector" }) do
        local r = rect(id)
        assert.is_true(r.x >= 0 and r.y >= 0 and r.x + r.w <= 640 and r.y + r.h <= 360, id)
      end
    end)

    it("resizes the sidebar by dragging its edge, and keeps the width", function()
      loupe.attach({ open = true, pick = false })
      love.draw()
      local x, y = at("loupe.split.sidebar")
      local before = rect("loupe.objects").w
      love.mousepressed(x, y, 1)
      love.draw()
      love.mousemoved(x + 60, y)
      love.draw()
      love.mousereleased(x + 60, y, 1)
      love.draw()
      local width = rect("loupe.objects").w
      assert.equal(before + 60, width)
      assert.equal(width, rect("loupe.inspector").w)
      resize(1200, 700)
      love.draw()
      assert.equal(width, rect("loupe.objects").w)
    end)

    it("moves the Objects/Inspector split by dragging between them", function()
      loupe.attach({ open = true, pick = false })
      love.draw()
      local before = rect("loupe.objects").h
      local x, y = at("loupe.split.sections")
      love.mousepressed(x, y, 1)
      love.draw()
      love.mousemoved(x, y + 50)
      love.draw()
      love.mousereleased(x, y + 50, 1)
      love.draw()
      assert.equal(before + 50, rect("loupe.objects").h)
    end)

    it("shows a resize cursor over a splitter", function()
      local set = {}
      love.mouse.getSystemCursor = function(name)
        return "cursor:" .. name
      end
      love.mouse.setCursor = function(cursor)
        set[#set + 1] = cursor or "default"
      end
      loupe.attach({ open = true, pick = false })
      love.draw()
      local x, y = at("loupe.split.sidebar")
      love.mousemoved(x, y)
      love.draw()
      love.draw()
      love.mousemoved(600, 400)
      love.draw()
      love.draw()
      assert.same({ "cursor:sizewe", "default" }, set)
    end)

    it("sizes the UI from attach({ uiScale })", function()
      loupe.attach({ open = true, uiScale = 2 })
      love.draw()
      local c = loupe._debugUi()
      assert.equal(2, c.theme.scale)
      assert.equal(2 * require("loupe.ui.theme").rowHeight, c.rowHeight)
    end)

    it("scales up by itself on very tall pixel-unit windows", function()
      resize(3840, 2160)
      loupe.attach({ open = true })
      love.draw()
      assert.equal(2, loupe._debugUi().theme.scale)
    end)

    it("merges attach({ theme }) without touching the shared theme", function()
      local themes = require("loupe.ui.theme")
      local before = themes.colors.accent[1]
      loupe.attach({ open = true, theme = { colors = { accent = { 1, 0, 0, 1 } }, radius = 2 } })
      love.draw()
      local c = loupe._debugUi()
      assert.same({ 1, 0, 0, 1 }, c.theme.colors.accent)
      assert.equal(2, c.theme.radius)
      assert.equal(before, themes.colors.accent[1])
      assert.same(themes.colors.text, c.theme.colors.text)
    end)

    it("passes Shift to number dragging for fine steps", function()
      local ship = { speed = 2 }
      loupe.watch(ship, "ship")
      loupe.attach({ open = true, pick = false })
      love.draw()
      clickOn("loupe.objects/ship")
      local x, y = at("loupe.inspector/speed", 10)
      fake.keysDown.lshift = true
      love.mousepressed(x, y, 1)
      love.draw()
      love.mousemoved(x + 10, y)
      love.draw()
      assert.is_true(math.abs(ship.speed - 2.05) < 1e-9)
    end)
  end)

  it("is reachable for specs through _debugUi only while attached", function()
    assert.is_nil(loupe._debugUi())
    loupe.attach()
    assert.truthy(loupe._debugUi().rectOf)
  end)

  it("passes text input through when no loupe field is focused", function()
    local typed
    love.textinput = function(t)
      typed = t
    end
    loupe.attach({ open = true })
    love.textinput("a")
    assert.equal("a", typed)
  end)

  it("accepts custom keys", function()
    loupe.attach({ keys = { toggle = "f12" } })
    love.keypressed("f1")
    assert.same({ { "keypressed", "f1" } }, gameCalls)
    love.keypressed("f12")
    assert.is_true(loupe.isOpen())
  end)

  it("is idempotent", function()
    loupe.attach()
    assert.has_no.errors(function()
      loupe.attach()
    end)
  end)

  it("detach restores the game's callbacks", function()
    local update = rawget(love, "update")
    loupe.attach()
    loupe.detach()
    assert.is_false(loupe.isAttached())
    assert.equal(update, rawget(love, "update"))
    assert.is_nil(getmetatable(love))
  end)

  describe("keys loupe used stay loupe's", function()
    local released, typedByGame

    before_each(function()
      released, typedByGame = {}, {}
      love.keyreleased = function(key)
        released[#released + 1] = key
      end
      love.textinput = function(t)
        typedByGame[#typedByGame + 1] = t
      end
    end)

    -- A key press and release as LÖVE delivers them: key, scancode, isrepeat.
    local function tap(key, text)
      love.keypressed(key, key, false)
      if text then
        love.textinput(text)
      end
      love.keyreleased(key, key)
    end

    it("swallows the release of F1", function()
      loupe.attach()
      tap("f1")
      assert.is_true(loupe.isOpen())
      tap("f1")
      assert.same({}, released)
    end)

    it("swallows a time hotkey's release and text while open", function()
      loupe.attach({ open = true })
      tap("p", "p")
      assert.is_true(loupe._debugUi() ~= nil)
      assert.same({}, released)
      assert.same({}, typedByGame)
    end)

    it("still gives the game keys loupe didn't use, with their text", function()
      loupe.attach({ open = true })
      tap("q", "q")
      assert.same({ "q" }, released)
      assert.same({ "q" }, typedByGame)
      loupe.setOpen(false)
      tap("p", "p")
      assert.same({ "q", "p" }, released)
      assert.same({ "q", "p" }, typedByGame)
    end)

    it("swallows only the text of the hotkey press itself", function()
      loupe.attach({ open = true })
      love.keypressed("p", "p", false)
      love.update(0.016) -- the press's text, if any, would have come before this
      love.textinput("x")
      assert.same({ "x" }, typedByGame)
    end)

    it("lets the game keep the release of a key it got the press of", function()
      loupe.attach()
      love.keypressed("a", "a", false)
      tap("f1")
      love.keyreleased("a", "a")
      assert.same({ "a" }, released)
    end)

    it("matches a release by scancode when the key name changed", function()
      loupe.attach()
      love.keypressed("f1", "f1", false)
      love.keyreleased("unknown", "f1")
      assert.same({}, released)
      love.keyreleased("unknown", "f1") -- only once
      assert.same({ "unknown" }, released)
    end)

    it("swallows the release of keys typed into a field, and of Ctrl/Cmd shortcuts", function()
      local player = { name = "bob" }
      loupe.watch(player, "player")
      loupe.attach({ open = true, pick = false })
      love.draw()
      clickOn("loupe.objects/player")
      clickOn("loupe.inspector/name")
      tap("backspace")
      fake.keysDown.lctrl = true
      tap("s")
      fake.keysDown.lctrl = nil
      tap("return")
      love.draw()
      assert.equal("bo", player.name)
      assert.same({}, released)
    end)
  end)

  describe("selection and the system clipboard in fields", function()
    local clipboard

    before_each(function()
      clipboard = ""
      love.system = {
        getClipboardText = function()
          return clipboard
        end,
        setClipboardText = function(s)
          clipboard = s
        end,
      }
    end)

    local function editName(player)
      loupe.watch(player, "player")
      loupe.attach({ open = true, pick = false })
      love.draw()
      clickOn("loupe.objects/player")
      clickOn("loupe.inspector/name")
    end

    local function ctrl(key)
      fake.keysDown.lgui = true -- Cmd counts as Ctrl
      love.keypressed(key, key, false)
      fake.keysDown.lgui = nil
    end

    it("copies with Ctrl/Cmd+A, Ctrl/Cmd+C and pastes with Ctrl/Cmd+V", function()
      local player = { name = "bob" }
      editName(player)
      ctrl("a")
      ctrl("c")
      love.draw()
      assert.equal("bob", clipboard)
      clipboard = "zed\nline two"
      ctrl("a")
      ctrl("v")
      love.keypressed("return")
      love.draw()
      assert.equal("zed\nline two", player.name)
    end)

    it("cuts with Ctrl/Cmd+X", function()
      local player = { name = "bob" }
      editName(player)
      ctrl("a")
      ctrl("x")
      love.keypressed("return")
      love.draw()
      assert.equal("bob", clipboard)
      assert.equal("", player.name)
    end)

    it("extends a selection with Shift and the arrow keys", function()
      local player = { name = "bob" }
      editName(player)
      fake.keysDown.lshift = true
      love.keypressed("left")
      fake.keysDown.lshift = nil
      love.textinput("x")
      love.keypressed("return")
      love.draw()
      assert.equal("box", player.name)
    end)
  end)

  describe("multi-line strings", function()
    local function printedLines()
      local out = {}
      for _, call in ipairs(fake.calls) do
        if call[1] == "print" then
          out[#out + 1] = tostring(call[2])
        end
      end
      return out
    end

    it("draws keys and values with newlines on one line each", function()
      loupe.watch({ ["two\nlines"] = { note = "a\nb" } }, "game")
      loupe.attach({ open = true, pick = false })
      love.draw()
      -- Tree ids are the key's label: ["two\<newline>lines"].
      local keyLabel = require("loupe.core.reflect").keyLabel("two\nlines")
      clickOn("game/" .. keyLabel)
      for i = #fake.calls, 1, -1 do
        fake.calls[i] = nil
      end
      love.draw()
      local lines = printedLines()
      assert.is_true(#lines > 0)
      for _, line in ipairs(lines) do
        assert.is_nil(line:find("%c"), line)
      end
      local joined = table.concat(lines, "|")
      assert.truthy(joined:find("a\\nb", 1, true))
    end)

    it("shows newlines and tabs as arrows when the fonts have them", function()
      -- render_love caches fonts across specs: start (and leave) it fresh.
      local function freshLoupe()
        package.loaded["loupe.ui.render_love"] = nil
        package.loaded["loupe"] = nil
        loupe = require("loupe")
      end
      freshLoupe()
      finally(function()
        loupe.detach()
        freshLoupe()
      end)
      rawset(love.graphics, "newFont", function()
        return {
          getWidth = function(_, text)
            return #text * 7
          end,
          getHeight = function()
            return 14
          end,
          hasGlyphs = function()
            return true
          end,
        }
      end)
      loupe.watch({ note = "a\nb\tc" }, "game")
      loupe.attach({ open = true, pick = false })
      love.draw()
      clickOn("loupe.objects/game")
      assert.is_true(drewText("a\226\134\181b\226\134\146c"))
    end)
  end)
end)
