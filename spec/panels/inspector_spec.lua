local driver = require("spec.support.ui_driver")
local inspector = require("loupe.panels.inspector")

local at = driver.at

describe("panels.inspector", function()
  local ctx, panel, selection
  local RECT = { x = 0, y = 300, w = 320, h = 400 }

  local step
  local function defaultStep(fields)
    return driver.frame(ctx, fields, function(c)
      panel:build(c, selection, RECT)
    end)
  end

  local function inspect(t, path)
    selection = { value = t, path = path or "obj" }
    step({})
  end

  -- Types into a field: replaces its text with `text` and commits.
  local function typeInto(key, text)
    step(driver.click(at(ctx, key)))
    local erase = {}
    for i = 1, 20 do
      erase[i] = "backspace"
    end
    step({ keys = erase })
    step({ text = text, keys = { "return" } })
  end

  before_each(function()
    ctx = driver.new()
    panel = inspector.new()
    selection = nil
    step = defaultStep
  end)

  it("says what to do when nothing is selected", function()
    assert.truthy(driver.findText(step({}), "Select"))
  end)

  it("is a docked section with an INSPECTOR header and a field count", function()
    inspect({ a = 1, b = 2 })
    local cmds = step({})
    assert.truthy(driver.findExact(cmds, "INSPECTOR"))
    assert.truthy(driver.findExact(cmds, "2 fields"))
  end)

  it("shows the selected path, keeping its end when long", function()
    inspect({}, "game.ship")
    assert.equal(ctx.theme.colors.accent, driver.findText(step({}), "game.ship")[5])
    inspect({}, "game.level.rooms[12].enemies[3].stats.weapons[2]")
    assert.matches("weapons%[2%]$", driver.findText(step({}), "weapons")[2])
  end)

  it("edits numbers by dragging", function()
    local t = { speed = 100 }
    inspect(t)
    local x, y = at(ctx, "speed", 10)
    step(driver.press(x, y))
    step(driver.hold(x + 20, y))
    assert.equal(110, t.speed)
  end)

  it("toggles booleans", function()
    local t = { alive = true }
    inspect(t)
    step(driver.click(at(ctx, "alive")))
    assert.is_false(t.alive)
  end)

  it("edits strings", function()
    local t = { name = "bob" }
    inspect(t)
    step(driver.click(at(ctx, "name")))
    step({ text = "by", keys = { "return" } })
    assert.equal("bobby", t.name)
  end)

  it("expands colors into editable channels on click", function()
    local t = { tint = { 0.5, 0.5, 0.5, 1 } }
    inspect(t)
    assert.is_nil(driver.findText(step({}), "green"))
    step(driver.click(at(ctx, "tint")))
    assert.truthy(driver.findText(step({}), "green"))
    typeInto("tint/red", "1")
    assert.equal(1, t.tint[1])
  end)

  it("drags color channels smoothly, even from 1 or 0", function()
    local t = { tint = { 0.5, 0.5, 0.5, 1 } }
    inspect(t)
    step(driver.click(at(ctx, "tint")))
    step({})
    local x, y = at(ctx, "tint/alpha", 10)
    step(driver.press(x, y))
    step(driver.hold(x - 20, y))
    assert.is_true(math.abs(t.tint[4] - 0.9) < 1e-9)
  end)

  it("expands nested tables inline and edits inside them", function()
    local t = { def = { r = 10 } }
    inspect(t)
    assert.truthy(driver.findExact(step({}), "def"))
    assert.truthy(driver.findExact(step({}), "{1}"))
    step(driver.click(at(ctx, "def")))
    step({})
    typeInto("def/r", "7")
    assert.equal(7, t.def.r)
  end)

  describe("edit callback", function()
    local calls
    before_each(function()
      calls = {}
      local build = function(c)
        panel:build(c, selection, RECT, function(target, key, value, keys)
          calls[#calls + 1] = { key, value, keys }
          target[key] = value
        end)
      end
      step = function(fields)
        return driver.frame(ctx, fields, build)
      end
    end)

    it("reports nested edits with keys from the selection's root", function()
      local t = { def = { r = 10 } }
      selection = { value = t, path = "game.rock", root = "game", keys = { "rock" } }
      step({})
      step(driver.click(at(ctx, "def")))
      step({})
      typeInto("def/r", "7")
      assert.same({ { "r", 7, { "rock", "def", "r" } } }, calls)
    end)

    it("reports color channel edits down to the channel index", function()
      local t = { tint = { 0.5, 0.5, 0.5, 1 } }
      selection = { value = t, path = "p", root = "game", keys = {} }
      step({})
      step(driver.click(at(ctx, "tint")))
      step({})
      typeInto("tint/red", "1")
      assert.same({ { 1, 1, { "tint", 1 } } }, calls)
    end)
  end)

  it("shows empty nested tables without a chevron", function()
    inspect({ empty = {} })
    assert.equal(0, driver.count(step({}), "line"))
    inspect({ full = { 1 } })
    assert.equal(1, driver.count(step({}), "line"))
  end)

  describe("stale selection", function()
    local NOTE = "(no longer in the game)"

    it("notes under the path when the selection has left the game", function()
      selection = { value = { hp = 3 }, path = "game.rocks[2]", stale = true }
      local cmds = step({})
      local note = driver.findText(cmds, NOTE)
      assert.truthy(note)
      assert.equal(ctx.theme.colors.warning, note[5])
      assert.is_true(note[4] > driver.findText(cmds, "game.rocks[2]")[4])
      -- Fields are still shown below it.
      assert.truthy(driver.findText(cmds, "hp"))
    end)

    it("says nothing for a live selection", function()
      selection = { value = { hp = 3 }, path = "game.rocks[2]" }
      assert.is_nil(driver.findText(step({}), NOTE))
    end)
  end)

  it("marks cycles", function()
    local t = {}
    t.self = t
    inspect(t)
    local cmds = step({})
    assert.truthy(driver.findExact(cmds, "self"))
    assert.truthy(driver.findExact(cmds, "(cycle)"))
  end)

  it("shows values it can't edit as text", function()
    inspect({ update = print })
    local cmds = step({})
    assert.truthy(driver.findExact(cmds, "update"))
    assert.truthy(driver.findExact(cmds, "function"))
  end)

  it("caps very long tables", function()
    local t = {}
    for i = 1, inspector.MAX_FIELDS + 3 do
      t[i] = i
    end
    inspect(t)
    -- The note is the last row: scroll down to it (rows out of view aren't drawn).
    for _ = 1, 200 do
      step({ x = 50, y = 400, wheel = -1 })
    end
    assert.truthy(driver.findText(step({}), "3 more"))
  end)
end)
