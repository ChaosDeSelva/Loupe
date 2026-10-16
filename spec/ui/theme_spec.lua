local theme = require("loupe.ui.theme")

describe("ui.theme", function()
  it("is itself a usable theme at scale 1", function()
    assert.is_number(theme.rowHeight)
    assert.is_table(theme.colors.accent)
    assert.is_table(theme.fonts.body)
  end)

  it("defines every color role the widgets use", function()
    for _, role in ipairs({
      "surface",
      "surfaceRaised",
      "border",
      "text",
      "textMuted",
      "accent",
      "accentSoft",
      "warning",
      "danger",
      "selection",
      "focus",
    }) do
      assert.is_table(theme.colors[role], role)
      assert.equal(4, #theme.colors[role], role)
    end
  end)

  it("defines font roles with a file and a size", function()
    for _, role in ipairs({ "body", "small", "title", "mono" }) do
      assert.is_string(theme.fonts[role].file, role)
      assert.is_number(theme.fonts[role].size, role)
    end
  end)

  describe("build", function()
    it("returns a copy: changing it never touches the shared module", function()
      local t = theme.build()
      t.colors.accent[1] = 0
      t.rowHeight = 99
      t.fonts.body.size = 99
      assert.are_not.equal(0, theme.colors.accent[1])
      assert.are_not.equal(99, theme.rowHeight)
      assert.are_not.equal(99, theme.fonts.body.size)
    end)

    it("merges overrides, replacing colors whole and keeping the rest", function()
      local accent = { 1, 0, 0, 1 }
      local t = theme.build({ colors = { accent = accent }, radius = 2 })
      assert.same(accent, t.colors.accent)
      assert.are_not.equal(accent, t.colors.accent) -- copied, not shared
      assert.equal(2, t.radius)
      assert.same(theme.colors.text, t.colors.text)
      assert.equal(theme.rowHeight, t.rowHeight)
    end)

    it("leaves the overrides table alone", function()
      local overrides = { colors = { text = { 1, 1, 1, 1 } }, rowHeight = 30 }
      theme.build(overrides, 2)
      assert.equal(30, overrides.rowHeight)
      assert.same({ 1, 1, 1, 1 }, overrides.colors.text)
    end)

    it("scales sizes and font sizes, rounding to whole pixels", function()
      local t = theme.build(nil, 1.5)
      assert.equal(math.floor(theme.rowHeight * 1.5 + 0.5), t.rowHeight)
      assert.equal(math.floor(theme.fonts.body.size * 1.5 + 0.5), t.fonts.body.size)
      assert.equal(math.floor(theme.space.md * 1.5 + 0.5), t.space.md)
      assert.equal(1.5, t.scale)
    end)

    it("does not scale ratios, counts or colors", function()
      local t = theme.build(nil, 2)
      assert.equal(theme.labelRatio, t.labelRatio)
      assert.equal(theme.scrollRows, t.scrollRows)
      assert.same(theme.colors.surface, t.colors.surface)
    end)

    it("keeps hairlines at least one pixel", function()
      local t = theme.build({ hairline = 1 }, 0.5)
      assert.equal(1, t.hairline)
    end)

    it("scales overridden sizes too", function()
      local t = theme.build({ radius = 4 }, 2)
      assert.equal(8, t.radius)
    end)
  end)
end)
