local driver = require("spec.support.ui_driver")
local theme = require("loupe.ui.theme")

local frame, inWindow, at = driver.frame, driver.inWindow, driver.at

describe("ui.context", function()
  local ctx, colors
  before_each(function()
    ctx = driver.new()
    colors = ctx.theme.colors
  end)

  it("requires a measure function", function()
    assert.has_error(function()
      require("loupe.ui").new({})
    end)
  end)

  it("uses its own copy of the default theme", function()
    local c = require("loupe.ui").new({
      measure = function()
        return 0
      end,
    })
    assert.are_not.equal(theme.colors, c.theme.colors)
    assert.same(theme.colors.accent, c.theme.colors.accent)
  end)

  it("asks for line heights per font role when given a function", function()
    local c = require("loupe.ui").new({
      measure = function()
        return 0
      end,
      lineHeight = function(font)
        return font == "title" and 10 or 30
      end,
    })
    assert.equal(10, c:fontHeight("title"))
    assert.equal(30, c:fontHeight())
    -- Rows grow to fit a tall body font.
    assert.equal(34, c.rowHeight)
  end)

  it("swaps themes, recomputing the row height", function()
    ctx:setTheme(theme.build(nil, 2))
    assert.equal(2 * theme.rowHeight, ctx.rowHeight)
  end)

  describe("windows", function()
    it("draws a rounded card, a title and a clipped content area", function()
      local cmds = frame(ctx, {}, inWindow(function() end))
      local card = driver.findColor(cmds, "rect", colors.surfaceRaised)
      assert.same({ "rect", 10, 10, 200, 300 }, { unpack(card, 1, 5) })
      assert.equal(ctx.theme.radius, card.radius)
      assert.truthy(driver.findColor(cmds, "outline", colors.border))
      assert.equal("strong", driver.findExact(cmds, "Test").font)
      assert.equal(1, driver.count(cmds, "clip"))
      assert.equal(1, driver.count(cmds, "unclip"))
    end)

    it("only emits windows built this frame", function()
      frame(ctx, {}, inWindow(function() end))
      local cmds = frame(ctx, {}, function() end)
      assert.same({}, cmds)
    end)

    it("refuses nested windows and widgets outside a window", function()
      ctx:beginFrame(driver.input())
      ctx:beginWindow("a", "A", driver.WIN)
      assert.has_error(function()
        ctx:beginWindow("b", "B", driver.WIN)
      end)
      ctx:endWindow()
      assert.has_error(function()
        ctx:label("stray")
      end)
    end)

    it("moves when its title bar is dragged", function()
      local build = inWindow(function() end)
      frame(ctx, {}, build)
      frame(ctx, driver.press(50, 15), build)
      frame(ctx, driver.hold(80, 45), build)
      frame(ctx, driver.release(80, 45), build)
      frame(ctx, {}, build)
      local r = ctx:rectOf("w")
      assert.same({ 40, 40 }, { r.x, r.y })
    end)

    it("keeps its title bar on screen while dragged", function()
      local build = inWindow(function() end)
      frame(ctx, {}, build, 800, 600)
      frame(ctx, driver.press(50, 15), build, 800, 600)
      frame(ctx, driver.hold(-500, -300), build, 800, 600)
      assert.same({ 0, 0 }, { ctx:rectOf("w").x, ctx:rectOf("w").y })
      frame(ctx, driver.hold(5000, 5000), build, 800, 600)
      local r = ctx:rectOf("w")
      assert.same({ 800 - 200, 600 - ctx.theme.titleHeight }, { r.x, r.y })
    end)

    it("moves back on screen when the screen shrinks", function()
      local build = inWindow(function() end, { x = 700, y = 500, w = 200, h = 300 })
      frame(ctx, {}, build, 1000, 800)
      assert.same({ 700, 500 }, { ctx:rectOf("w").x, ctx:rectOf("w").y })
      frame(ctx, {}, build, 640, 480)
      local r = ctx:rectOf("w")
      assert.same({ 440, 480 - ctx.theme.titleHeight }, { r.x, r.y })
    end)

    it("brings a clicked window to the front", function()
      local function build(c)
        c:beginWindow("back", "Back", { x = 0, y = 0, w = 100, h = 100 })
        c:endWindow()
        c:beginWindow("front", "Front", { x = 50, y = 50, w = 100, h = 100 })
        c:endWindow()
      end
      frame(ctx, {}, build)
      frame(ctx, driver.click(20, 20), build)
      local cmds = frame(ctx, {}, build)
      -- The window drawn last is on top.
      local back, front
      for i, cmd in ipairs(cmds) do
        if cmd[1] == "text" and cmd[2] == "Back" then
          back = i
        elseif cmd[1] == "text" and cmd[2] == "Front" then
          front = i
        end
      end
      assert.is_true(back > front)
    end)

    it("hit-tests using the previous frame's windows", function()
      assert.is_false(ctx:wantsMouse(20, 20))
      frame(ctx, {}, inWindow(function() end))
      assert.is_true(ctx:wantsMouse(20, 20))
      assert.is_false(ctx:wantsMouse(500, 500))
      frame(ctx, {}, function() end)
      assert.is_false(ctx:wantsMouse(20, 20))
    end)

    it("keeps the mouse while a drag is in progress, even off-window", function()
      local build = inWindow(function() end)
      frame(ctx, {}, build)
      frame(ctx, driver.press(50, 15), build)
      assert.is_true(ctx:wantsMouse(900, 900))
    end)

    it("scrolls content with the wheel, clamped to the content", function()
      local rect = { x = 10, y = 10, w = 200, h = 100 }
      local build = inWindow(function(c)
        for i = 1, 20 do
          c:label("row " .. i)
        end
      end, rect)
      frame(ctx, {}, build)
      local first = driver.findExact(frame(ctx, {}, build), "row 3")
      frame(ctx, { x = 50, y = 50, wheel = -1 }, build)
      local scrolled = driver.findExact(frame(ctx, {}, build), "row 3")
      assert.is_true(scrolled[4] < first[4])

      for _ = 1, 50 do
        frame(ctx, { x = 50, y = 50, wheel = -1 }, build)
      end
      local cmds = frame(ctx, {}, build)
      local last = driver.findExact(cmds, "row 20")
      -- At max scroll the last row sits at the bottom of the view.
      local view = ctx.windows.w.content
      assert.is_true(last[4] >= view.y + view.h - ctx.rowHeight)
      assert.is_true(last[4] < view.y + view.h)
      local bar = driver.findColor(cmds, "rect", colors.scrollbar)
      assert.truthy(bar)
      assert.equal(ctx.theme.scrollbarWidth, bar[4])
      assert.truthy(bar.radius)
    end)

    it("shows no scrollbar when the content fits", function()
      local cmds = frame(
        ctx,
        {},
        inWindow(function(c)
          c:label("one")
        end)
      )
      assert.is_nil(driver.findColor(cmds, "rect", colors.scrollbar))
    end)

    it("scrolls by dragging the scrollbar thumb", function()
      local rect = { x = 10, y = 10, w = 200, h = 100 }
      local build = inWindow(function(c)
        for i = 1, 20 do
          c:label("row " .. i)
        end
      end, rect)
      frame(ctx, {}, build)
      local bar = driver.findColor(frame(ctx, {}, build), "rect", colors.scrollbar)
      local bx, by = bar[2] + 1, bar[3] + 2
      frame(ctx, driver.press(bx, by), build)
      assert.is_true(ctx:wantsMouse(bx, by))
      frame(ctx, driver.hold(bx, by + 500), build)
      frame(ctx, driver.release(bx, by + 500), build)
      local cmds = frame(ctx, {}, build)
      assert.truthy(driver.findExact(cmds, "row 20"))
      assert.is_nil(driver.findExact(cmds, "row 1"))
    end)

    describe("rows outside the view", function()
      -- 20 rows in a 100px window: only the first three are (partly) in view.
      local rect = { x = 10, y = 10, w = 200, h = 100 }
      local labels = inWindow(function(c)
        for i = 1, 20 do
          c:label("row " .. i)
        end
      end, rect)

      it("emit no draw commands", function()
        frame(ctx, {}, labels)
        local cmds = frame(ctx, {}, labels)
        local view = ctx.windows.w.content
        local step = ctx.rowHeight + ctx.theme.spacing
        local visible = math.ceil(view.h / step)
        assert.truthy(driver.findExact(cmds, "row 1"))
        assert.truthy(driver.findExact(cmds, "row " .. visible))
        assert.is_nil(driver.findExact(cmds, "row " .. visible + 1))
        assert.is_nil(driver.findExact(cmds, "row 20"))
        assert.equal(visible + 1, driver.count(cmds, "text")) -- the title and visible rows
      end)

      it("still count toward the content height", function()
        frame(ctx, {}, labels)
        local step = ctx.rowHeight + ctx.theme.spacing
        assert.equal(20 * step - ctx.theme.spacing, ctx.windows.w.contentHeight)
      end)

      it("appear once scrolled into view, and the ones scrolled past disappear", function()
        frame(ctx, {}, labels)
        for _ = 1, 50 do
          frame(ctx, { x = 50, y = 50, wheel = -1 }, labels)
        end
        local cmds = frame(ctx, {}, labels)
        assert.truthy(driver.findExact(cmds, "row 20"))
        assert.is_nil(driver.findExact(cmds, "row 1"))
      end)

      it("skip widget boxes too, while chrome and scrollbar still draw", function()
        local buttons = inWindow(function(c)
          for i = 1, 20 do
            c:button("b" .. i)
          end
        end, rect)
        frame(ctx, {}, buttons)
        local cmds = frame(ctx, {}, buttons)
        local boxes = 0
        for _, cmd in ipairs(cmds) do
          if cmd[1] == "rect" and cmd[6] == colors.control then
            boxes = boxes + 1
          end
        end
        assert.equal(3, boxes)
        assert.truthy(driver.findColor(cmds, "rect", colors.scrollbar))
        assert.equal(1, driver.count(cmds, "unclip"))
        -- And their rects aren't recorded: nothing to click there.
        assert.truthy(ctx:rectOf("w/b1"))
        assert.is_nil(ctx:rectOf("w/b10"))
      end)
    end)

    it("draws every row of an auto-height window, even before it has grown", function()
      local rect = { x = 0, y = 0, w = 100, h = 10, autoHeight = true }
      local cmds = frame(
        ctx,
        {},
        inWindow(function(c)
          c:label("one")
          c:label("two")
        end, rect)
      )
      assert.truthy(driver.findExact(cmds, "one"))
      assert.truthy(driver.findExact(cmds, "two"))
    end)

    it("sizes itself to its content in the same frame", function()
      local rect = { x = 0, y = 0, w = 100, h = 10, autoHeight = true }
      local cmds = frame(
        ctx,
        {},
        inWindow(function(c)
          c:label("one")
          c:label("two")
        end, rect)
      )
      local t = ctx.theme
      local expected = t.titleHeight + 2 * ctx.rowHeight + t.spacing + t.padding
      assert.equal(expected, driver.findColor(cmds, "rect", colors.surfaceRaised)[5])
      assert.equal(expected, ctx:rectOf("w").h)
    end)
  end)

  describe("docked panels", function()
    local function panel(rect)
      return function(c)
        rect.docked = true
        c:beginWindow("p", "Objects", rect)
        c:button("Go")
        c:endWindow()
      end
    end

    it("follow the rect they're given every frame", function()
      frame(ctx, {}, panel({ x = 0, y = 40, w = 300, h = 400 }))
      frame(ctx, {}, panel({ x = 0, y = 40, w = 360, h = 700 }))
      local r = ctx:rectOf("p")
      assert.same({ 0, 40, 360, 700 }, { r.x, r.y, r.w, r.h })
    end)

    it("don't move when their header is dragged", function()
      local build = panel({ x = 0, y = 40, w = 300, h = 400 })
      frame(ctx, {}, build)
      frame(ctx, driver.press(50, 45), build)
      frame(ctx, driver.hold(150, 145), build)
      local r = ctx:rectOf("p")
      assert.same({ 0, 40 }, { r.x, r.y })
    end)

    it("draw a flat surface with an uppercase muted header and a right-hand note", function()
      local cmds = frame(ctx, {}, function(c)
        c:beginWindow("p", "Objects", {
          x = 0,
          y = 0,
          w = 300,
          h = 200,
          docked = true,
          headerRight = "3",
          edges = { right = true, top = true },
        })
        c:endWindow()
      end)
      local bg = driver.findColor(cmds, "rect", colors.surface)
      assert.is_nil(bg.radius)
      local header = driver.findExact(cmds, "OBJECTS")
      assert.equal(colors.textMuted, header[5])
      assert.equal("title", header.font)
      local note = driver.findExact(cmds, "3")
      assert.is_true(note[3] > 250)
      local hairlines = 0
      for _, cmd in ipairs(cmds) do
        if cmd[1] == "rect" and cmd[6] == colors.border then
          hairlines = hairlines + 1
        end
      end
      assert.equal(2, hairlines)
    end)

    it("can grow to fit when auto-height, without clipping its rows", function()
      local function build(c)
        c:beginWindow(
          "pop",
          "Keys",
          { x = 0, y = 0, w = 200, h = 10, popover = true, autoHeight = true }
        )
        for i = 1, 5 do
          c:label("key " .. i)
        end
        c:endWindow()
      end
      local cmds = frame(ctx, {}, build)
      local clip
      for _, cmd in ipairs(cmds) do
        if cmd[1] == "clip" then
          clip = cmd
        end
      end
      local last = driver.findExact(cmds, "key 5")
      assert.is_true(last[4] < clip[3] + clip[5])
      frame(ctx, {}, build)
      local t = ctx.theme
      local expected = t.headerHeight + 5 * ctx.rowHeight + 4 * t.spacing + t.padding
      assert.equal(expected, ctx:rectOf("pop").h)
    end)

    it("leave a gutter for the scrollbar when content overflows", function()
      local count = 3
      local function build(c)
        c:beginWindow("p", "P", { x = 0, y = 0, w = 300, h = 200, docked = true })
        for i = 1, count do
          c:button("b" .. i, { width = 1000 })
        end
        c:endWindow()
      end
      frame(ctx, {}, build)
      local wide = ctx.windows.p.content.w
      count = 30
      frame(ctx, {}, build)
      frame(ctx, {}, build)
      local narrow = ctx.windows.p.content.w
      assert.equal(wide - ctx.theme.scrollbarWidth - ctx.theme.space.sm, narrow)
    end)

    it("can hide the header", function()
      local cmds = frame(ctx, {}, function(c)
        c:beginWindow(
          "bar",
          "Bar",
          { x = 0, y = 0, w = 300, h = 40, docked = true, header = false }
        )
        c:button("Go")
        c:endWindow()
      end)
      assert.is_nil(driver.findExact(cmds, "BAR"))
      assert.equal(ctx.theme.padding, ctx:rectOf("bar/Go").y)
    end)

    it("are never brought in front of a later window", function()
      local function build(c)
        c:beginWindow("dock", "Dock", { x = 0, y = 0, w = 100, h = 100, docked = true })
        c:endWindow()
        c:beginWindow("pop", "Pop", { x = 50, y = 50, w = 100, h = 100, popover = true })
        c:endWindow()
      end
      frame(ctx, {}, build)
      frame(ctx, driver.click(10, 10), build)
      local cmds = frame(ctx, {}, build)
      local dock, pop
      for i, cmd in ipairs(cmds) do
        if cmd[2] == "DOCK" then
          dock = i
        elseif cmd[2] == "POP" then
          pop = i
        end
      end
      assert.is_true(pop > dock)
      -- Popovers draw as raised cards.
      assert.truthy(driver.findColor(cmds, "rect", colors.surfaceRaised))
    end)
  end)

  describe("splitter", function()
    local pos, held, hovered
    local function build(c)
      c:beginWindow("left", "Left", { x = 0, y = 0, w = 300, h = 400, docked = true })
      c:button("Edge##edge", {})
      c:endWindow()
      hovered, held, pos = c:splitter("split", 296, 0, 8, 400, "x")
    end

    it("reports where the divider should go while dragged", function()
      frame(ctx, {}, build)
      frame(ctx, driver.press(298, 100), build)
      assert.is_true(held)
      frame(ctx, driver.hold(350, 120), build)
      -- Pressed 2px left of center (300): the divider follows, keeping that offset.
      assert.equal(352, pos)
      frame(ctx, driver.release(350, 120), build)
      frame(ctx, { x = 350, y = 120 }, build)
      assert.is_false(held)
      assert.is_nil(pos)
    end)

    it("takes the mouse ahead of the window under it", function()
      frame(ctx, {}, build)
      assert.is_true(ctx:wantsMouse(298, 100))
      assert.is_true(ctx:wantsMouse(400, 100) == false)
      local cmds = frame(ctx, { x = 298, y = 5 }, build)
      assert.is_true(hovered)
      -- The hover line is drawn after (over) the windows.
      local line = driver.findColor(cmds, "rect", colors.focus)
      assert.truthy(line)
      assert.equal(cmds[#cmds], line)
    end)

    it("draws nothing when not hovered", function()
      frame(ctx, {}, build)
      local cmds = frame(ctx, { x = 100, y = 100 }, build)
      assert.is_false(hovered)
      assert.is_nil(driver.findColor(cmds, "rect", colors.focus))
      assert.is_nil(driver.findColor(cmds, "rect", colors.accent))
    end)
  end)

  describe("rectOf", function()
    it("records last frame's widget boxes by id", function()
      local build = inWindow(function(c)
        c:button("Go")
        c:pushId("sub")
        c:button("Go")
        c:popId()
      end)
      assert.is_nil(ctx:rectOf("w/Go"))
      frame(ctx, {}, build)
      local a, b = ctx:rectOf("w/Go"), ctx:rectOf("w/sub/Go")
      assert.truthy(a and b)
      assert.is_true(b.y > a.y)
      local x, y = at(ctx, "sub/Go")
      assert.same({ b.x + math.floor(b.w / 2), b.y + math.floor(b.h / 2) }, { x, y })
    end)

    it("forgets widgets that weren't drawn", function()
      local show = true
      local build = inWindow(function(c)
        if show then
          c:button("Go")
        end
      end)
      frame(ctx, {}, build)
      show = false
      frame(ctx, {}, build)
      assert.is_nil(ctx:rectOf("w/Go"))
      assert.has_error(function()
        at(ctx, "Go")
      end)
    end)
  end)

  describe("fitText", function()
    it("returns text that fits unchanged", function()
      ctx:beginFrame(driver.input())
      assert.equal("abc", ctx:fitText("abc", 21))
      ctx:endFrame()
    end)

    it("keeps the longest prefix that fits with the ellipsis", function()
      for width = 14, 70 do
        local fitted = ctx:fitText(("x"):rep(40), width)
        local kept = #fitted - 2
        assert.is_true(#fitted * 7 <= width, width)
        assert.is_true((kept + 1 + 2) * 7 > width, width)
      end
    end)

    it("never splits a multi-byte character", function()
      local fitted = ctx:fitText(("é"):rep(20), 7 * 9)
      assert.equal(("é"):rep(3) .. "..", fitted) -- 3 x 2 bytes + 2 dots = 8 bytes
    end)

    it("measures a logarithmic number of times, not once per character", function()
      local calls = 0
      local c = require("loupe.ui").new({
        measure = function(text)
          calls = calls + 1
          return #text * 7
        end,
      })
      calls = 0
      c:fitText(("x"):rep(5000), 300)
      assert.is_true(calls <= 16, calls)
    end)

    it("can keep the end instead", function()
      assert.equal("..def", ctx:fitTextStart("abcdef", 6 * 7 - 1))
      assert.equal("abcdef", ctx:fitTextStart("abcdef", 6 * 7))
      local calls = 0
      local c = require("loupe.ui").new({
        measure = function(text)
          calls = calls + 1
          return #text * 7
        end,
      })
      calls = 0
      assert.equal(".." .. ("x"):rep(40), c:fitTextStart(("x"):rep(5000), 42 * 7))
      assert.is_true(calls <= 16, calls)
    end)
  end)

  describe("ids", function()
    it("scopes ids with pushId/popId", function()
      ctx:beginFrame(driver.input())
      ctx:beginWindow("w", "W", driver.WIN)
      local plain = ctx:id("x")
      ctx:pushId("child")
      local scoped = ctx:id("x")
      ctx:popId()
      assert.are_not.equal(plain, scoped)
      assert.equal(plain, ctx:id("x"))
      ctx:endWindow()
      ctx:endFrame()
    end)
  end)

  it("wants the keyboard only while a field is being edited", function()
    local build = inWindow(function(c)
      c:textField("name", "bob")
    end)
    frame(ctx, {}, build)
    assert.is_false(ctx:wantsKeyboard())
    frame(ctx, driver.click(at(ctx, "name")), build)
    assert.is_true(ctx:wantsKeyboard())
  end)
end)
