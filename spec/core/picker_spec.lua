local geometry = require("loupe.core.geometry")
local picker = require("loupe.core.picker")

local function input(fields)
  local snapshot = { x = -100, y = -100, down = false, pressed = false, released = false }
  for k, v in pairs(fields or {}) do
    snapshot[k] = v
  end
  return snapshot
end

-- World is drawn at 2x zoom, shifted right by 100 screen pixels.
local view = {
  toWorld = function(sx, sy)
    return (sx - 100) / 2, sy / 2
  end,
  toScreen = function(wx, wy)
    return wx * 2 + 100, wy * 2
  end,
}

describe("core.picker", function()
  local p, crate, roots

  local function frame(fields, free)
    local list = geometry.collect(roots, {})
    return p:frame(input(fields), free ~= false, list, view)
  end

  before_each(function()
    p = picker.new()
    crate = { x = 10, y = 10, w = 10, h = 10 } -- screen box: (120, 20) to (140, 40)
    roots = { { name = "level", value = { crate = crate } } }
  end)

  it("reports what's under the pointer, through the view transform", function()
    assert.equal(crate, frame({ x = 130, y = 30 }).hover.value)
    assert.is_nil(frame({ x = 10, y = 30 }).hover)
  end)

  it("picks on press", function()
    local result = frame({ x = 130, y = 30, pressed = true, down = true })
    assert.equal(crate, result.picked.value)
    assert.equal("level.crate", result.picked.path)
  end)

  it("routes drag writes through the given setter, with the entry", function()
    local writes = {}
    local list = geometry.collect(roots, {})
    local function set(entry, key, value)
      writes[#writes + 1] = { entry.root, entry.keys[1], key, value }
      entry.value[key] = value
    end
    p:frame(input({ x = 130, y = 30, pressed = true, down = true }), true, list, view, set)
    p:frame(input({ x = 150, y = 30, down = true }), true, list, view, set)
    assert.same({ { "level", "crate", "x", 20 }, { "level", "crate", "y", 10 } }, writes)
  end)

  it("ignores presses that the UI owns", function()
    local result = frame({ x = 130, y = 30, pressed = true, down = true }, false)
    assert.is_nil(result.picked)
    assert.is_nil(result.hover)
  end)

  it("drags in world units", function()
    frame({ x = 130, y = 30, pressed = true, down = true })
    frame({ x = 150, y = 40, down = true }) -- +20, +10 screen = +10, +5 world
    assert.same({ 20, 15 }, { crate.x, crate.y })
    frame({ x = 150, y = 40, released = true })
    frame({ x = 200, y = 40, down = true })
    assert.same({ 20, 15 }, { crate.x, crate.y }) -- released: no longer dragging
  end)

  it("keeps dragging when the pointer crosses a window", function()
    frame({ x = 130, y = 30, pressed = true, down = true })
    frame({ x = 150, y = 30, down = true }, false)
    assert.equal(20, crate.x)
  end)

  it("ignores jitter below the drag threshold", function()
    frame({ x = 130, y = 30, pressed = true, down = true })
    frame({ x = 131, y = 31, down = true })
    assert.same({ 10, 10 }, { crate.x, crate.y })
  end)

  it("doesn't drag objects without numeric x, y", function()
    local thing = { pos = { 10, 10 } }
    roots = { { name = "t", value = thing } }
    local opts = {
      bounds = function(o)
        if o.pos then
          return o.pos[1], o.pos[2], 10, 10
        end
      end,
    }
    local list = geometry.collect(roots, opts)
    p:frame(input({ x = 130, y = 30, pressed = true, down = true }), true, list, view)
    p:frame(input({ x = 170, y = 30, down = true }), true, list, view)
    assert.same({ 10, 10 }, thing.pos)
  end)

  describe("stacked objects", function()
    local mid, big

    -- Screen boxes: crate (120, 20)-(140, 40), mid (110, 10)-(160, 60), big
    -- (100, 0)-(300, 200).
    before_each(function()
      mid = { x = 5, y = 5, w = 25, h = 25 }
      big = { x = 0, y = 0, w = 100, h = 100 }
      roots = { { name = "level", value = { crate = crate, mid = mid, big = big } } }
    end)

    local function click(x, y)
      return frame({ x = x, y = y, pressed = true, released = true }).picked.value
    end

    it("picks the smallest first, then the next one up on each click at the same spot", function()
      assert.equal(crate, click(130, 30))
      assert.equal(mid, click(130, 30))
      assert.equal(big, click(130, 30))
      assert.equal(crate, click(130, 30)) -- wraps around
    end)

    it("still cycles when the pointer moved a pixel or two", function()
      assert.equal(crate, click(130, 30))
      assert.equal(mid, click(131, 31))
    end)

    it("starts over from the smallest after a click somewhere else", function()
      assert.equal(crate, click(130, 30))
      assert.equal(mid, click(130, 30))
      assert.equal(crate, click(138, 38))
    end)

    it("starts over after a click on empty space", function()
      assert.equal(crate, click(130, 30))
      frame({ x = 10, y = 30, pressed = true, released = true })
      assert.equal(crate, click(130, 30))
    end)

    it("cycles on release, so a press can drag the object it cycled to", function()
      assert.equal(crate, click(130, 30))
      assert.equal(mid, click(130, 30))
      -- Pressing again keeps mid, and dragging moves mid, not crate.
      local pressed = frame({ x = 130, y = 30, pressed = true, down = true })
      assert.equal(mid, pressed.picked.value)
      frame({ x = 150, y = 30, down = true })
      local released = frame({ x = 150, y = 30, released = true })
      assert.same({ 15, 5 }, { mid.x, mid.y })
      assert.same({ 10, 10 }, { crate.x, crate.y })
      assert.is_nil(released.picked) -- a drag isn't a click: no cycling
    end)

    it("doesn't cycle when a drag comes back to where it started", function()
      assert.equal(crate, click(130, 30))
      frame({ x = 130, y = 30, pressed = true, down = true })
      frame({ x = 150, y = 30, down = true })
      frame({ x = 130, y = 30, down = true })
      assert.is_nil(frame({ x = 130, y = 30, released = true }).picked)
    end)

    it("cycles on a release in a later frame than the press", function()
      assert.equal(crate, click(130, 30))
      frame({ x = 130, y = 30, pressed = true, down = true })
      local released = frame({ x = 130, y = 30, released = true })
      assert.equal(mid, released.picked.value)
    end)

    it("hovers the smallest box", function()
      assert.equal(crate, frame({ x = 130, y = 30 }).hover.value)
    end)
  end)

  describe("highlight", function()
    -- A style like the UI theme's, with a 7px-per-byte font 14px tall.
    local style = {
      colors = {
        textMuted = "muted",
        accent = "accent",
        accentSoft = "soft",
        textOnAccent = "onAccent",
      },
      measure = function(text)
        return #text * 7
      end,
      lineHeight = 14,
    }
    local area = { x = 0, y = 0, w = 800, h = 600 }

    local function find(cmds, kind, color)
      for _, cmd in ipairs(cmds) do
        local c = kind == "text" and cmd[5] or cmd[6]
        if cmd[1] == kind and c == color then
          return cmd
        end
      end
    end

    it("outlines the hovered and selected boxes in screen space, rounded", function()
      local cmds = picker.highlight(
        { x = 10, y = 10, w = 10, h = 10 },
        { x = 0, y = 50, w = 5, h = 5, path = "level.crate" },
        view,
        style,
        area
      )
      local hover = find(cmds, "outline", "muted")
      assert.same({ "outline", 120, 20, 20, 20 }, { unpack(hover, 1, 5) })
      assert.truthy(hover.radius)
      local selected = find(cmds, "outline", "accent")
      assert.same({ "outline", 100, 100, 10, 10 }, { unpack(selected, 1, 5) })
      assert.equal(2, selected.width)
      assert.same({ "rect", 100, 100, 10, 10 }, { unpack(find(cmds, "rect", "soft"), 1, 5) })
    end)

    it("labels the selection with its path in an accent pill above it", function()
      local cmds =
        picker.highlight(nil, { x = 0, y = 50, w = 5, h = 5, path = "p" }, view, style, area)
      local pill = find(cmds, "rect", "accent")
      local label = find(cmds, "text", "onAccent")
      assert.equal("p", label[2])
      assert.equal("small", label.font)
      assert.is_true(pill[3] + pill[5] <= 100) -- ends above the box
      assert.is_true(label[3] > pill[2] and label[3] + 7 < pill[2] + pill[4])
      assert.equal(pill[5] / 2, pill.radius)
    end)

    it("puts the label below a box at the top edge", function()
      local cmds = picker.highlight(
        nil,
        { x = 0, y = 0, w = 5, h = 5, path = "level.crate" },
        view,
        style,
        area
      )
      local pill = find(cmds, "rect", "accent")
      assert.is_true(pill[3] >= 10) -- below the box's screen bottom (y 0..10)
    end)

    it("keeps the label inside the area at the right edge", function()
      local cmds = picker.highlight(
        nil,
        { x = 340, y = 50, w = 5, h = 5, path = "a.long.path.name" },
        view,
        style,
        area
      )
      local pill = find(cmds, "rect", "accent")
      assert.equal(800, pill[2] + pill[4])
    end)

    it("clips everything to the area, so outlines never draw over loupe's panels", function()
      local cmds = picker.highlight({ x = 1, y = 1, w = 1, h = 1 }, nil, view, style, area)
      assert.same({ "clip", 0, 0, 800, 600 }, cmds[1])
      assert.same({ "unclip" }, cmds[#cmds])
    end)

    it("draws nothing without boxes", function()
      assert.same({}, picker.highlight(nil, nil, view, style, area))
    end)
  end)
end)
