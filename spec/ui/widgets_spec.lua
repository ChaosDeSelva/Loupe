local driver = require("spec.support.ui_driver")

local frame, inWindow, row, at = driver.frame, driver.inWindow, driver.row, driver.at
local CHAR = driver.CHAR

-- Builds `fn` in the test window each frame and lets tests feed it input.
local function harness(fn)
  local ctx = driver.new()
  local build = inWindow(fn)
  frame(ctx, {}, build) -- first frame registers the window and widget rects
  return function(fields)
    return frame(ctx, fields, build)
  end, ctx
end

describe("ui widgets", function()
  describe("label", function()
    it("draws its text", function()
      local step = harness(function(c)
        c:label("hello")
      end)
      assert.truthy(driver.findText(step(), "hello"))
    end)

    it("truncates text that doesn't fit", function()
      local step, ctx = harness(function(c)
        c:label(("x"):rep(100))
      end)
      local cmd = driver.findText(step(), "x")
      assert.matches("%.%.$", cmd[2])
      local width = ctx.windows.w.content.w
      assert.is_true(#cmd[2] * CHAR <= width)
      -- The longest cut that fits: one more character wouldn't.
      assert.is_true((#cmd[2] + 1) * CHAR > width)
    end)

    it("draws in a font role when asked", function()
      local step = harness(function(c)
        c:label("42", nil, "mono")
      end)
      assert.equal("mono", driver.findText(step(), "42").font)
    end)
  end)

  describe("pathLabel", function()
    it("keeps the end of a long path", function()
      local step, ctx = harness(function(c)
        c:pathLabel("game.level.rooms[12].enemies[3].stats.hp")
      end)
      local cmd = driver.findText(step(), "hp")
      assert.matches("^%.%.", cmd[2])
      assert.matches("stats%.hp$", cmd[2])
      assert.is_true(#cmd[2] * CHAR <= ctx.windows.w.content.w)
    end)
  end)

  describe("button", function()
    local clicks, step, ctx
    before_each(function()
      clicks = 0
      step, ctx = harness(function(c)
        if c:button("Go") then
          clicks = clicks + 1
        end
      end)
    end)

    it("reports a click inside it", function()
      step(driver.click(at(ctx, "Go")))
      assert.equal(1, clicks)
    end)

    it("ignores clicks elsewhere", function()
      local r = driver.rect(ctx, "Go")
      step(driver.click(r.x + r.w + 10, r.y + 5))
      step(driver.click(r.x + 5, r.y + r.h + 10))
      assert.equal(0, clicks)
    end)

    it("doesn't click when the press is released outside", function()
      local r = driver.rect(ctx, "Go")
      step(driver.press(at(ctx, "Go")))
      step(driver.release(r.x + r.w + 10, r.y + 5))
      assert.equal(0, clicks)
    end)

    it("highlights on hover", function()
      local x, y = at(ctx, "Go")
      assert.is_nil(driver.findColor(step({}), "rect", ctx.theme.colors.controlHover))
      step({ x = x, y = y })
      assert.truthy(driver.findColor(step({ x = x, y = y }), "rect", ctx.theme.colors.controlHover))
    end)

    it("is rounded", function()
      local cmd = driver.findColor(step({}), "rect", ctx.theme.colors.control)
      assert.equal(ctx.theme.radiusSmall, cmd.radius)
    end)

    it("hides an '##id' suffix and uses it to tell buttons apart", function()
      local hits = {}
      local s, c2 = harness(function(c)
        if c:button("Go##a") then
          hits[#hits + 1] = "a"
        end
        if c:button("Go##b") then
          hits[#hits + 1] = "b"
        end
      end)
      local cmds = s(driver.click(at(c2, "b")))
      assert.same({ "b" }, hits)
      assert.is_nil(driver.findText(cmds, "##"))
    end)

    it("sits beside the previous widget after sameLine", function()
      local second = 0
      local s, c2 = harness(function(c)
        c:button("One")
        c:sameLine()
        if c:button("Two") then
          second = second + 1
        end
      end)
      local one, two = driver.rect(c2, "One"), driver.rect(c2, "Two")
      assert.equal(one.y, two.y)
      assert.equal(one.x + one.w + c2.theme.spacing, two.x)
      s(driver.click(at(c2, "Two")))
      assert.equal(1, second)
    end)

    it("ignores clicks while disabled and draws its label faint", function()
      local n = 0
      local s, c2 = harness(function(c)
        if c:button("Undo", { disabled = true }) then
          n = n + 1
        end
      end)
      local cmds = s(driver.click(at(c2, "Undo")))
      assert.equal(0, n)
      assert.equal(c2.theme.colors.textFaint, driver.findExact(cmds, "Undo")[5])
    end)

    it("draws primary buttons in the accent color", function()
      local s, c2 = harness(function(c)
        c:button("Save", { primary = true })
      end)
      assert.truthy(driver.findColor(s({}), "rect", c2.theme.colors.accent))
    end)

    it("draws an icon with or without a label", function()
      local s = harness(function(c)
        c:button("Pause", { icon = "pause" })
        c:button("##step", { icon = "step" })
        c:button("##more", { icon = "plus" })
      end)
      local cmds = s({})
      assert.truthy(driver.findExact(cmds, "Pause"))
      assert.equal(1, driver.count(cmds, "poly")) -- the step triangle
      assert.equal(2, driver.count(cmds, "line")) -- the plus
    end)
  end)

  describe("segmented", function()
    it("reports which part was clicked", function()
      local clicked
      local s, ctx = harness(function(c)
        clicked = c:segmented(
          { "##slower", "x1##reset", "##faster" },
          { icons = { "minus", nil, "plus" } }
        )
      end)
      s(driver.click(at(ctx, "faster")))
      assert.equal(3, clicked)
      s(driver.click(at(ctx, "reset")))
      assert.equal(2, clicked)
      s({})
      assert.is_nil(clicked)
      local slower, reset = driver.rect(ctx, "slower"), driver.rect(ctx, "reset")
      assert.equal(slower.x + slower.w, reset.x) -- joined, no gap
    end)
  end)

  describe("toggle", function()
    it("flips on click and shows its state", function()
      local value, changed = false, nil
      local s, ctx = harness(function(c)
        value, changed = c:toggle("Pick", value)
      end)
      assert.is_nil(driver.findColor(s({}), "rect", ctx.theme.colors.accent))
      s(driver.click(at(ctx, "Pick")))
      assert.is_true(value)
      assert.is_true(changed)
      assert.truthy(driver.findColor(s({}), "rect", ctx.theme.colors.accent))
      assert.is_false(changed)
    end)
  end)

  describe("checkbox", function()
    it("toggles when its value area is clicked", function()
      local value, changedCount = false, 0
      local step, ctx = harness(function(c)
        local changed
        value, changed = c:checkbox("on", value)
        if changed then
          changedCount = changedCount + 1
        end
      end)
      step(driver.click(at(ctx, "on")))
      assert.is_true(value)
      step(driver.click(at(ctx, "on")))
      assert.is_false(value)
      assert.equal(2, changedCount)
    end)

    it("draws a check mark only when checked", function()
      local value = true
      local step = harness(function(c)
        value = c:checkbox("on", value)
      end)
      assert.equal(1, driver.count(step({}), "line"))
      value = false
      assert.equal(0, driver.count(step({}), "line"))
    end)
  end)

  describe("dragNumber", function()
    local value, opts, step, ctx, x0, y

    before_each(function()
      value, opts = 10, {}
      step, ctx = harness(function(c)
        value = c:dragNumber("speed", value, opts)
      end)
      x0, y = at(ctx, "speed", 10)
    end)

    it("changes with horizontal drag", function()
      opts.speed = 0.5
      step(driver.press(x0, y))
      step(driver.hold(x0 + 40, y))
      assert.equal(30, value)
      step(driver.hold(x0 + 20, y))
      assert.equal(20, value)
      step(driver.release(x0 + 20, y))
    end)

    it("ignores tiny jitters below the drag threshold", function()
      step(driver.press(x0, y))
      step(driver.hold(x0 + 1, y))
      assert.equal(10, value)
    end)

    it("clamps and rounds", function()
      opts.speed, opts.min, opts.max, opts.integer = 0.3, 0, 12, true
      step(driver.press(x0, y))
      step(driver.hold(x0 + 5, y))
      assert.equal(12, value)
      step(driver.hold(x0 - 20, y))
      assert.equal(4, value)
    end)

    it("scales the default speed with the value's size", function()
      value = 1000
      step(driver.press(x0, y))
      step(driver.hold(x0 + 10, y))
      assert.equal(1050, value)
    end)

    describe("integer-aware dragging", function()
      it("drags a whole number in whole steps", function()
        value = 2 -- default speed 0.05: 10px is +0.5
        step(driver.press(x0, y))
        step(driver.hold(x0 + 10, y))
        assert.equal(3, value)
        step(driver.hold(x0 + 14, y))
        assert.equal(3, value) -- 2.7 rounds to 3, never 2.7
      end)

      it("drags a fractional number smoothly", function()
        value = 2.25
        step(driver.press(x0, y))
        step(driver.hold(x0 + 10, y))
        assert.equal(2.75, value)
      end)

      it("drags a whole number finely, and slower, while Shift is held", function()
        value = 2
        step(driver.press(x0, y))
        step({ x = x0 + 10, y = y, down = true, shift = true })
        assert.is_true(math.abs(value - 2.05) < 1e-9)
      end)

      it("keeps whole steps with Shift when the caller asked for integers", function()
        value, opts.integer, opts.speed = 2, true, 1
        step(driver.press(x0, y))
        step({ x = x0 + 14, y = y, down = true, shift = true })
        assert.equal(3, value) -- 2 + 1.4, rounded
      end)

      it("can be turned off with integer = false", function()
        value, opts.integer = 2, false
        step(driver.press(x0, y))
        step(driver.hold(x0 + 10, y))
        assert.equal(2.5, value)
      end)
    end)

    it("draws its value in the mono font, in a rounded field", function()
      local cmds = step({})
      assert.equal("mono", driver.findExact(cmds, "10").font)
      assert.truthy(driver.findColor(cmds, "rect", ctx.theme.colors.field).radius)
    end)

    describe("click to type", function()
      before_each(function()
        step(driver.click(x0, y))
        assert.is_true(ctx:wantsKeyboard())
      end)

      it("commits a typed number on enter", function()
        step({ keys = { "backspace", "backspace" } })
        step({ text = "42.5", keys = { "return" } })
        assert.equal(42.5, value)
        assert.is_false(ctx:wantsKeyboard())
      end)

      it("shows the text being typed, with a focus ring", function()
        local cmds = step({ text = "7" })
        assert.truthy(driver.findText(cmds, "107"))
        assert.truthy(driver.findColor(cmds, "outline", ctx.theme.colors.focus))
      end)

      it("cancels on escape", function()
        step({ text = "99", keys = { "escape" } })
        assert.equal(10, value)
        assert.is_false(ctx:wantsKeyboard())
      end)

      it("keeps the old value when the text isn't a number", function()
        step({ text = "abc", keys = { "return" } })
        assert.equal(10, value)
      end)

      it("commits when clicking elsewhere", function()
        step({ typed = { { key = "backspace" }, { key = "backspace" }, { text = "3" } } })
        step(driver.click(20, row(5)))
        assert.equal(3, value)
        assert.is_false(ctx:wantsKeyboard())
      end)

      it("clamps typed values", function()
        opts.max = 5
        step({ text = "0", keys = { "return" } })
        assert.equal(5, value)
      end)

      it("types at the cursor", function()
        step({ typed = { { key = "home" }, { text = "-" }, { key = "return" } } })
        assert.equal(-10, value)
      end)
    end)
  end)

  describe("textField", function()
    local value, step, ctx

    before_each(function()
      value = "café"
      step, ctx = harness(function(c)
        value = c:textField("name", value)
      end)
    end)

    -- Where the field's text starts.
    local function textX()
      return driver.rect(ctx, "name").x + ctx.theme.controlPadding
    end

    it("edits after a click and commits on enter", function()
      step(driver.click(at(ctx, "name")))
      step({ keys = { "backspace" } }) -- removes the whole two-byte 'é'
      step({ text = "s", keys = { "return" } })
      assert.equal("cafs", value)
    end)

    it("reports no change when the text is the same", function()
      local changed
      local s, c2 = harness(function(c)
        local _, ch = c:textField("name", "same")
        changed = changed or ch
      end)
      s(driver.click(at(c2, "name")))
      s({ keys = { "return" } })
      assert.is_false(changed or false)
    end)

    it("drops the edit when the field stops being drawn", function()
      local show = true
      local s, c2 = harness(function(c)
        if show then
          c:textField("name", "x")
        end
      end)
      s(driver.click(at(c2, "name")))
      assert.is_true(c2:wantsKeyboard())
      show = false
      s({})
      assert.is_false(c2:wantsKeyboard())
    end)

    it("does not edit when clicked outside", function()
      local r = driver.rect(ctx, "name")
      step(driver.click(r.x + 5, r.y + r.h + 20))
      assert.is_false(ctx:wantsKeyboard())
    end)

    describe("cursor", function()
      local function keys(...)
        local typed = {}
        for i, k in ipairs({ ... }) do
          typed[i] = k:sub(1, 1) == "@" and { key = k:sub(2) } or { text = k }
        end
        return step({ typed = typed })
      end

      local function caretX(cmds)
        for _, cmd in ipairs(cmds) do
          if cmd[1] == "rect" and cmd[4] == 1 then
            return cmd[2]
          end
        end
      end

      before_each(function()
        step(driver.click(at(ctx, "name")))
      end)

      it("inserts typed text at the cursor after moving left", function()
        keys("@left", "X", "@return")
        assert.equal("cafX\195\169", value)
      end)

      it("jumps to the start with home and back to the end with end", function()
        keys("@home", "X", "@end", "!", "@return")
        assert.equal("Xcaf\195\169!", value)
      end)

      it("backspaces the character before the cursor", function()
        keys("@left", "@backspace", "@return")
        assert.equal("ca\195\169", value)
      end)

      it("deletes the character after the cursor, whole even when multi-byte", function()
        keys("@left", "@delete", "@return")
        assert.equal("caf", value)
      end)

      it("steps over a multi-byte character as one", function()
        keys("@left", "@left", "@right", "X", "@return")
        assert.equal("cafX\195\169", value)
      end)

      it("ignores moves and deletes past either end", function()
        keys("@home", "@left", "@backspace", "X", "@end", "@right", "@delete", "Y", "@return")
        assert.equal("Xcaf\195\169Y", value)
      end)

      it("draws the caret where the cursor is", function()
        -- The test font is 7px per byte; "café" is 5 bytes.
        assert.equal(textX() + 5 * CHAR, caretX(step({})))
        assert.equal(textX() + 3 * CHAR, caretX(keys("@left")))
        assert.equal(textX(), caretX(keys("@home")))
      end)

      it("draws the text without a fake caret character", function()
        local cmds = step({})
        assert.equal("caf\195\169", driver.findText(cmds, "caf")[2])
      end)

      it("places the cursor with a click inside the field", function()
        -- Nearest boundary to 2 chars + 2px is after "ca".
        step(driver.click(textX() + 2 * CHAR + 2, select(2, at(ctx, "name"))))
        assert.is_true(ctx:wantsKeyboard())
        keys("X", "@return")
        assert.equal("caXf\195\169", value)
      end)
    end)

    describe("long text", function()
      local long = ("a"):rep(30) .. "END"
      local s, c2, shownText, visible

      before_each(function()
        s, c2 = harness(function(c)
          c:textField("name", long)
        end)
        s(driver.click(at(c2, "name")))
        shownText = function(cmds)
          for _, cmd in ipairs(cmds) do
            if cmd[1] == "text" and cmd[2]:find("^a") then
              return cmd[2]
            end
          end
        end
        -- Characters that fit: the field minus padding both sides and a 1px caret.
        local r = driver.rect(c2, "name")
        visible = math.floor((r.w - 2 * c2.theme.controlPadding - 1) / CHAR)
      end)

      it("keeps the end visible while the cursor is there", function()
        local text = shownText(s({}))
        assert.matches("END$", text)
        assert.is_true(#text < #long)
        assert.equal(visible, #text)
      end)

      it("scrolls to the start on home, cutting the end off", function()
        local text = shownText(s({ keys = { "home" } }))
        assert.equal(("a"):rep(visible), text)
      end)

      it("scrolls only as far as needed while moving right from the start", function()
        s({ keys = { "home" } })
        local typed = {}
        for i = 1, 15 do
          typed[i] = { key = "right" }
        end
        local text = shownText(s({ typed = typed }))
        -- Cursor after 15 chars: the view starts 15 - visible chars in.
        assert.equal(("a"):rep(visible), text)
        local back = {}
        for i = 1, 5 do
          back[i] = { key = "left" }
        end
        -- Moving left inside the view doesn't scroll it.
        local cmds = s({ typed = back })
        local caret
        for _, cmd in ipairs(cmds) do
          if cmd[1] == "rect" and cmd[4] == 1 then
            caret = cmd[2]
          end
        end
        local x = driver.rect(c2, "name").x + c2.theme.controlPadding
        assert.equal(x + (10 - (15 - visible)) * CHAR, caret)
      end)
    end)
  end)

  describe("treeNode", function()
    local childClicks, step, opened, ctx
    before_each(function()
      childClicks = 0
      step, ctx = harness(function(c)
        opened = c:treeNode("player")
        if opened then
          if c:button("child") then
            childClicks = childClicks + 1
          end
          c:treePop()
        end
        c:label("after")
      end)
    end)

    it("starts closed and opens on click", function()
      step({})
      assert.is_false(opened)
      step(driver.click(at(ctx, "player")))
      assert.is_true(opened)
      step(driver.click(at(ctx, "player")))
      assert.is_false(opened)
    end)

    it("indents its children", function()
      step(driver.click(at(ctx, "player")))
      local cmds = step({})
      local child = driver.findText(cmds, "child")
      local after = driver.findText(cmds, "after")
      assert.is_true(child[3] > after[3])
      assert.equal(
        driver.rect(ctx, "player").x + ctx.theme.indent,
        driver.rect(ctx, "player/child").x
      )
      step(driver.click(at(ctx, "player/child")))
      assert.equal(1, childClicks)
    end)

    -- The chevron's middle point says which way it points.
    local function chevron(cmds)
      for _, cmd in ipairs(cmds) do
        if cmd[1] == "line" and #cmd[2] == 6 then
          local p = cmd[2]
          return p[3] > p[1] and p[4] == (p[2] + p[6]) / 2 and "right" or "down"
        end
      end
    end

    it("draws a chevron that shows whether it's open", function()
      assert.equal("right", chevron(step({})))
      step(driver.click(at(ctx, "player")))
      assert.equal("down", chevron(step({})))
    end)

    describe("selectable", function()
      local open, picked, pick, c2
      before_each(function()
        pick, c2 = harness(function(c)
          open, picked = c:treeNode("node", { selectable = true, selected = picked })
          if open then
            c:treePop()
          end
        end)
      end)

      it("selects on a label click without toggling", function()
        pick(driver.click(at(c2, "node", c2.theme.indent + 20)))
        assert.is_false(open)
        assert.is_true(picked)
      end)

      it("toggles on a chevron click without selecting", function()
        -- The chevron zone is the first `indent` pixels of the row.
        pick(driver.click(at(c2, "node", 4)))
        assert.is_true(open)
        assert.is_false(picked)
      end)

      it("highlights the selected node with a rounded pill", function()
        local s, c3 = harness(function(c)
          c:treeNode("node", { selectable = true, selected = true })
        end)
        local pill = driver.findColor(s({}), "rect", c3.theme.colors.selection)
        assert.truthy(pill)
        assert.equal(c3.theme.radiusSmall, pill.radius)
      end)
    end)

    describe("leaf", function()
      local open, picked, leaf, c2
      before_each(function()
        leaf, c2 = harness(function(c)
          open, picked = c:treeNode("node", { leaf = true, selectable = true, open = true })
          if open then
            c:treePop()
          end
          c:label("after")
        end)
      end)

      it("draws no chevron and never opens, even when asked to start open", function()
        local cmds = leaf({})
        assert.is_false(open)
        assert.equal(0, driver.count(cmds, "line"))
        local row1 = driver.rect(c2, "node")
        -- The label lines up with siblings' labels, after where a chevron would be.
        assert.equal(
          row1.x + c2.theme.indent + c2.theme.space.xs,
          driver.findExact(cmds, "node")[3]
        )
        -- Nothing was indented under it.
        assert.equal(row1.x, driver.findText(cmds, "after")[3])
      end)

      it("picks on a click anywhere on the row, including the chevron zone", function()
        leaf(driver.click(at(c2, "node", 4)))
        assert.is_false(open)
        assert.is_true(picked)
        leaf(driver.click(at(c2, "node")))
        assert.is_false(open)
        assert.is_true(picked)
      end)

      it("does nothing on click when not selectable", function()
        local o, p
        local s, c3 = harness(function(c)
          o, p = c:treeNode("plain", { leaf = true })
        end)
        s(driver.click(at(c3, "plain", 4)))
        assert.is_false(o)
        assert.is_false(p)
      end)
    end)

    it("right-aligns a muted count", function()
      local s, c2 = harness(function(c)
        c:treeNode("rocks", { count = "12" })
      end)
      local cmds = s({})
      local count = driver.findExact(cmds, "12")
      local r = driver.rect(c2, "rocks")
      assert.equal("small", count.font)
      assert.equal(c2.theme.colors.textFaint, count[5])
      assert.is_true(count[3] + 2 * CHAR <= r.x + r.w)
      assert.is_true(count[3] + 2 * CHAR >= r.x + r.w - 10)
      assert.is_true(driver.findExact(cmds, "rocks")[3] < count[3])
    end)

    it("can start open", function()
      local open
      local s = harness(function(c)
        open = c:treeNode("x", { open = true })
        if open then
          c:treePop()
        end
      end)
      s({})
      assert.is_true(open)
    end)
  end)

  describe("colorSwatch", function()
    it("draws the color and its hex value, and reports clicks", function()
      local color = { 1, 0, 0, 0.5 }
      local clicked
      local ctx = driver.new()
      local build = inWindow(function(c)
        clicked = c:colorSwatch("tint", color)
      end, { x = 0, y = 0, w = 400, h = 200 })
      frame(ctx, {}, build)
      local cmds = frame(ctx, driver.click(at(ctx, "tint")), build)
      assert.is_true(clicked)
      local swatch = driver.findColor(cmds, "rect", color)
      assert.truthy(swatch)
      assert.truthy(swatch.radius)
      assert.truthy(driver.findExact(cmds, "#FF0000  50%"))
    end)
  end)

  it("valueRow shows a read-only value beside its label", function()
    local step = harness(function(c)
      c:valueRow("update", "function")
    end)
    local cmds = step({})
    local label, value = driver.findExact(cmds, "update"), driver.findExact(cmds, "function")
    assert.equal(label[4], value[4])
    assert.is_true(value[3] > label[3])
    assert.equal("mono", value.font)
  end)

  it("separator takes a thin row", function()
    local step = harness(function(c)
      c:separator()
      c:label("below")
    end)
    local below = driver.findText(step({}), "below")
    assert.is_true(below[4] < row(2))
  end)

  it("divider and spacer take room on a row", function()
    local step, ctx = harness(function(c)
      c:button("A")
      c:sameLine()
      c:divider()
      c:sameLine()
      c:spacer(30)
      c:sameLine()
      c:button("B")
    end)
    step({})
    local a, b = driver.rect(ctx, "A"), driver.rect(ctx, "B")
    local t = ctx.theme
    local gap = (t.space.md + t.hairline) + 30 + 3 * t.spacing
    assert.equal(a.x + a.w + gap, b.x)
  end)

  it("alignRight puts a widget flush with the right edge", function()
    local step, ctx = harness(function(c)
      c:button("A")
      local w = c:buttonWidth("Z")
      c:alignRight(w)
      c:button("Z")
    end)
    step({})
    local z, content = driver.rect(ctx, "Z"), ctx.windows.w.content
    assert.equal(content.x + content.w, z.x + z.w)
    assert.equal(driver.rect(ctx, "A").y, z.y)
  end)
end)
