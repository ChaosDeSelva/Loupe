local clockModule = require("loupe.core.clock")
local driver = require("spec.support.ui_driver")
local toolbar = require("loupe.panels.toolbar")

local at = driver.at

local KEYS =
  { toggle = "f1", pause = "p", step = ".", slower = "[", faster = "]", resetSpeed = "1" }

describe("panels.toolbar", function()
  local ctx, clock, tools, action, width

  local function rect()
    return { x = 0, y = 0, w = width, h = toolbar.height(ctx, width, clock, tools) }
  end

  local function step(fields)
    return driver.frame(ctx, fields, function(c)
      action = toolbar.build(c, rect(), clock, KEYS, tools)
    end)
  end

  local function click(key)
    step(driver.click(at(ctx, key)))
    return action
  end

  before_each(function()
    ctx = driver.new()
    clock = clockModule.new()
    tools = { picking = true, canUndo = true, canRedo = true }
    width = 1600
    step({})
  end)

  it("pauses and resumes, showing the state", function()
    assert.truthy(driver.findExact(step({}), "RUNNING"))
    click("pause")
    assert.is_true(clock.paused)
    local cmds = step({})
    assert.truthy(driver.findExact(cmds, "PAUSED"))
    assert.truthy(driver.findExact(cmds, "Resume"))
    click("pause")
    assert.is_false(clock.paused)
  end)

  it("steps and changes speed", function()
    click("pause")
    click("step")
    assert.equal(1, clock.pendingSteps)
    click("faster")
    assert.equal(2, clock.scale)
    assert.truthy(driver.findExact(step({}), "x2"))
    click("reset")
    assert.equal(1, clock.scale)
    click("slower")
    assert.is_true(clock.scale < 1)
  end)

  it("switches world picking with the Pick toggle", function()
    click("pick")
    assert.is_false(tools.picking)
    click("pick")
    assert.is_true(tools.picking)
  end)

  it("returns undo, redo and save when clicked", function()
    assert.equal("undo", click("Undo"))
    assert.equal("redo", click("Redo"))
    assert.equal("save", click("Save"))
    step({})
    assert.is_nil(action)
  end)

  it("disables Undo and Redo when there's nothing to do", function()
    tools.canUndo, tools.canRedo = false, false
    step({})
    assert.is_nil(click("Undo"))
    assert.is_nil(click("Redo"))
  end)

  it("shows unsaved changes and makes Save the primary button", function()
    local function saveFilled(cmds)
      local save = driver.rect(ctx, "Save")
      for _, cmd in ipairs(cmds) do
        if cmd[1] == "rect" and cmd[6] == ctx.theme.colors.accent then
          if cmd[2] == save.x and cmd[3] == save.y then
            return true
          end
        end
      end
      return false
    end
    local cmds = step({})
    assert.is_nil(driver.findText(cmds, "unsaved"))
    assert.is_false(saveFilled(cmds))
    tools.dirty = true
    step({})
    cmds = step({})
    assert.truthy(driver.findExact(cmds, "unsaved changes"))
    assert.is_true(saveFilled(cmds))
  end)

  it("shows the latest status message in its color", function()
    tools.status, tools.statusColor = "reload failed: src.ship", ctx.theme.colors.warning
    local cmd = driver.findText(step({}), "reload failed")
    assert.equal(ctx.theme.colors.warning, cmd[5])
  end)

  it("lines the right-hand buttons up with the bar's right edge", function()
    local help = driver.rect(ctx, "help")
    assert.equal(width - ctx.theme.space.lg, help.x + help.w)
    assert.equal(driver.rect(ctx, "pause").y, help.y)
  end)

  it("uses one row when wide and two when narrow", function()
    local t = ctx.theme
    local one = ctx.rowHeight + 2 * t.barPadding
    assert.equal(one, toolbar.height(ctx, 1600, clock, tools))
    assert.equal(2 * one - 2 * t.barPadding + t.spacing, toolbar.height(ctx, 640, clock, tools))
  end)

  it("keeps every control inside the bar when narrow", function()
    width = 640
    tools.dirty, tools.status = true, "saved 3 overrides to a very long path somewhere"
    step({})
    step({})
    local bar = rect()
    for id, r in pairs(ctx.rects) do
      if id:find("^loupe%.toolbar/") then
        assert.is_true(r.x >= 0 and r.x + r.w <= width, id)
        assert.is_true(r.y >= 0 and r.y + r.h <= bar.h, id)
      end
    end
    local status = driver.findText(step({}), "saved 3")
    assert.is_true(#status[2] * driver.CHAR <= width)
  end)

  it("opens a key reference from the ? button", function()
    assert.is_nil(driver.findText(step({}), "Step one frame"))
    click("help")
    assert.is_true(tools.help)
    local cmds = step({})
    assert.truthy(driver.findText(cmds, "Step one frame"))
    assert.truthy(driver.findExact(cmds, "F1"))
    -- The popover sits under the bar, inside the screen.
    local pop = ctx:rectOf("loupe.help")
    assert.is_true(pop.y >= rect().h)
    assert.is_true(pop.x + pop.w <= width)
    click("help")
    assert.is_nil(driver.findText(step({}), "Step one frame"))
  end)

  it("closes the key reference on a click outside it, but not inside", function()
    click("help")
    step({})
    step(driver.click(at(ctx, "loupe.help")))
    assert.is_true(tools.help)
    step(driver.click(5, 500))
    assert.is_false(tools.help)
  end)
end)
