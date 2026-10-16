local layout = require("loupe.panels.layout")
local themes = require("loupe.ui.theme")

describe("panels.layout", function()
  local theme = themes.build()
  local BAR = 40

  local function compute(w, h, split, t)
    return layout.compute(w, h, t or theme, split or {}, BAR)
  end

  local function inside(r, w, h)
    return r.x >= 0 and r.y >= 0 and r.w >= 0 and r.h >= 0 and r.x + r.w <= w and r.y + r.h <= h
  end

  it("puts a full-width bar on top and the sidebar below it on the left", function()
    local r = compute(1280, 720)
    assert.same({ x = 0, y = 0, w = 1280, h = BAR }, r.bar)
    assert.same({ 0, BAR }, { r.sidebar.x, r.sidebar.y })
    assert.equal(720 - BAR, r.sidebar.h)
  end)

  it("stacks Objects over Inspector, filling the sidebar exactly", function()
    local r = compute(1280, 720)
    assert.equal(r.sidebar.y, r.objects.y)
    assert.equal(r.objects.y + r.objects.h, r.inspector.y)
    assert.equal(720, r.inspector.y + r.inspector.h)
    assert.equal(r.sidebar.w, r.objects.w)
    assert.equal(r.sidebar.w, r.inspector.w)
    -- Objects gets the default share.
    assert.equal(math.floor((720 - BAR) * theme.objectsRatio + 0.5), r.objects.h)
  end)

  it("leaves the uncovered area free for the game", function()
    local r = compute(1280, 720)
    assert.same({ x = r.sidebar.w, y = BAR, w = 1280 - r.sidebar.w, h = 720 - BAR }, r.free)
  end)

  describe("default sidebar width", function()
    it("is a share of the screen", function()
      assert.equal(math.floor(1500 * theme.sidebarRatio + 0.5), compute(1500, 900).sidebar.w)
    end)

    it("never gets narrower than the default minimum", function()
      assert.equal(theme.sidebarDefaultMin, compute(1000, 700).sidebar.w)
    end)

    it("never gets wider than the default maximum", function()
      assert.equal(theme.sidebarDefaultMax, compute(2560, 1440).sidebar.w)
    end)

    it("scales with the UI", function()
      local big = themes.build(nil, 2)
      assert.equal(2 * theme.sidebarDefaultMin, compute(1000, 700, {}, big).sidebar.w)
    end)
  end)

  describe("dragged sidebar width", function()
    it("is kept in unscaled units, so it follows UI scale changes", function()
      assert.equal(380, compute(1600, 900, { sidebar = 380 }).sidebar.w)
      local big = themes.build(nil, 2)
      assert.equal(760, compute(3200, 1800, { sidebar = 380 }, big).sidebar.w)
    end)

    it("converts a drag position back to unscaled units", function()
      local big = themes.build(nil, 2)
      assert.equal(380, layout.sidebarFromDrag(760, big))
      assert.equal(380, layout.sidebarFromDrag(380, theme))
    end)

    it("is clamped so the game keeps some room, without forgetting the choice", function()
      local split = { sidebar = 900 }
      local r = compute(1000, 700, split)
      assert.equal(1000 - theme.freeMin, r.sidebar.w)
      assert.equal(900, split.sidebar) -- back to 900 when the window grows again
      assert.equal(900, compute(1600, 900, split).sidebar.w)
    end)

    it("has a minimum", function()
      assert.equal(theme.sidebarMin, compute(1600, 900, { sidebar = 20 }).sidebar.w)
    end)
  end)

  describe("Objects/Inspector split", function()
    it("follows the stored ratio", function()
      local r = compute(1280, 740, { objects = 0.25 })
      assert.equal(math.floor(700 * 0.25 + 0.5), r.objects.h)
    end)

    it("keeps both sections at least their minimum height", function()
      local min = theme.panelMinHeight
      assert.equal(min, compute(1280, 740, { objects = 0 }).objects.h)
      assert.equal(min, compute(1280, 740, { objects = 1 }).inspector.h)
    end)

    it("converts a drag position to a ratio of the sidebar", function()
      local r = compute(1280, 740)
      assert.equal(0.5, layout.objectsFromDrag(BAR + 350, r))
      assert.equal(0, layout.objectsFromDrag(-100, r))
      assert.equal(1, layout.objectsFromDrag(5000, r))
    end)
  end)

  it("puts splitter handles centered on the edges they move", function()
    local r = compute(1280, 720)
    local s = r.sidebarSplitter
    assert.equal(r.sidebar.w, s.x + s.w / 2)
    assert.same({ BAR, 720 - BAR }, { s.y, s.h })
    local o = r.sectionSplitter
    assert.equal(r.inspector.y, o.y + o.h / 2)
    assert.same({ 0, r.sidebar.w }, { o.x, o.w })
  end)

  it("keeps everything on screen for any window size", function()
    for _, size in ipairs({ { 320, 200 }, { 100, 60 }, { 0, 0 }, { 640, 360 }, { 3840, 2160 } }) do
      local w, h = size[1], size[2]
      local splits = { {}, { sidebar = 5000, objects = 0.9 }, { sidebar = 1, objects = 0 } }
      for _, split in ipairs(splits) do
        local r = compute(w, h, split)
        for _, name in ipairs({ "bar", "sidebar", "objects", "inspector", "free" }) do
          assert.is_true(inside(r[name], w, h), ("%s at %dx%d"):format(name, w, h))
        end
        assert.equal(w, r.sidebar.w + r.free.w)
      end
    end
  end)
end)
