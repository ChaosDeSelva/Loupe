local love_stub = require("spec.support.love_stub")
local theme = require("loupe.ui.theme")

describe("ui.render_love", function()
  local fake, render, fontCalls

  local function calls(name)
    local out = {}
    for _, call in ipairs(fake.calls) do
      if call[1] == name then
        out[#out + 1] = call
      end
    end
    return out
  end

  before_each(function()
    fake = love_stub.install()
    fontCalls = {}
    rawset(love.graphics, "newFont", function(...)
      local args = { ... }
      fontCalls[#fontCalls + 1] = args
      local size = type(args[1]) == "number" and args[1] or args[2]
      return {
        args = args,
        getWidth = function(_, text)
          return #text * size
        end,
        getHeight = function()
          return size + 4
        end,
      }
    end)
    package.loaded["loupe.ui.render_love"] = nil
    render = require("loupe.ui.render_love")
  end)

  after_each(function()
    love_stub.uninstall()
  end)

  describe("fonts", function()
    it("falls back to LÖVE's default font at the role's size when files are missing", function()
      -- The stub's filesystem has no font files, and io can't hand bytes to
      -- LÖVE without newFileData, so every role falls back.
      render.configure(theme.build(nil, 2))
      assert.equal(5 * 26, render.measure("hello", "body"))
      assert.equal(22 + 4, render.lineHeight("small"))
      assert.equal("number", type(fontCalls[1][1]))
    end)

    it("defaults to the body role", function()
      render.configure(theme.build())
      assert.equal(render.measure("abc", "body"), render.measure("abc"))
      assert.equal(render.lineHeight("body"), render.lineHeight())
    end)

    it("loads a role's file through love.filesystem when the game can see it", function()
      fake.files["loupe/fonts/Inter-Regular.ttf"] = "bytes"
      render.configure(theme.build())
      render.measure("x", "body")
      assert.equal("loupe/fonts/Inter-Regular.ttf", fontCalls[1][1])
      assert.equal(13, fontCalls[1][2])
    end)

    it("reads the file with io when loupe lives outside the game folder", function()
      local made = {}
      love.filesystem.newFileData = function(bytes, name)
        made[#made + 1] = { bytes = bytes, name = name }
        return { fileData = name }
      end
      render.configure(theme.build())
      render.measure("x", "mono")
      -- The real file next to this checkout was read and handed to LÖVE.
      assert.equal("JetBrainsMono-Regular.ttf", made[1].name)
      assert.is_true(#made[1].bytes > 1000)
      assert.same({ fileData = "JetBrainsMono-Regular.ttf" }, fontCalls[1][1])
    end)

    it("falls back when LÖVE rejects a font file", function()
      fake.files["loupe/fonts/Inter-Regular.ttf"] = "not a font"
      local real = love.graphics.newFont
      rawset(love.graphics, "newFont", function(a, ...)
        if type(a) == "string" then
          error("Could not load font")
        end
        return real(a, ...)
      end)
      render.configure(theme.build())
      assert.equal(13 * 2, render.measure("ab", "body"))
    end)

    it("creates each font once and again when the DPI scale changes", function()
      render.configure(theme.build())
      render.measure("x", "body")
      render.measure("y", "body")
      assert.equal(1, #fontCalls)
      rawset(love.graphics, "getDPIScale", function()
        return 2
      end)
      render.draw({ { "text", "hi", 0, 0, { 1, 1, 1, 1 } } })
      assert.equal(2, #fontCalls)
      assert.equal(2, fontCalls[2][3]) -- rasterized for the new density
    end)
  end)

  describe("draw", function()
    before_each(function()
      render.configure(theme.build())
    end)

    it("draws rounded rectangles and outlines", function()
      local c = { 1, 0, 0, 1 }
      render.draw({
        { "rect", 1, 2, 30, 40, c, radius = 6 },
        { "outline", 1, 2, 30, 40, c, radius = 6, width = 2 },
      })
      local rects = calls("rectangle")
      assert.same({ "rectangle", "fill", 1, 2, 30, 40, 6, 6 }, { unpack(rects[1], 1, 8) })
      -- Outlines sit inside the box: inset by half the line width.
      assert.same({ "rectangle", "line", 2, 3, 28, 38, 5, 5 }, { unpack(rects[2], 1, 8) })
    end)

    it("prints text in the requested font role, on whole pixels", function()
      render.draw({ { "text", "42", 10.6, 20.2, { 1, 1, 1, 1 }, font = "mono" } })
      local prints = calls("print")
      assert.same({ "print", "42", 10, 20 }, prints[1])
      local fonts = calls("setFont")
      local args = fonts[#fonts][2].args
      assert.equal(12, type(args[1]) == "number" and args[1] or args[2])
    end)

    it("never prints more than one line, whatever text a command carries", function()
      -- The UI escapes text itself; this guards text built outside it
      -- (such as core/picker's path pill).
      render.draw({ { "text", "a\nb", 0, 0, { 1, 1, 1, 1 } } })
      assert.equal("a\\nb", calls("print")[1][2])
    end)

    it("draws lines, circles and polygons", function()
      local c = { 1, 1, 1, 1 }
      render.draw({
        { "line", { 0, 0, 5, 5, 10, 0 }, c, width = 2 },
        { "circle", 5, 6, 3, c },
        { "poly", { 0, 0, 4, 0, 2, 3 }, c },
      })
      assert.same({ 0, 0, 5, 5, 10, 0 }, calls("line")[1][2])
      assert.same({ "circle", "fill", 5, 6, 3 }, { unpack(calls("circle")[1], 1, 5) })
      assert.same({ "polygon", "fill", { 0, 0, 4, 0, 2, 3 } }, calls("polygon")[1])
    end)

    it("clips and unclips", function()
      render.draw({ { "clip", 1, 2, -5, 4 }, { "unclip" } })
      local s = calls("setScissor")
      -- One reset at the start, the clip (negative sizes clamp to 0), the unclip.
      assert.same({ "setScissor", 1, 2, 0, 4 }, s[2])
      assert.same({ "setScissor" }, s[3])
    end)

    it("always restores the graphics state, even when a command fails", function()
      assert.has_error(function()
        render.draw({ { "rect", 0, 0, 1, 1, { 1, 1, 1, 1 } }, { "bogus" } })
      end, "loupe: unknown draw command 'bogus'")
      assert.equal(1, #calls("push"))
      assert.equal(1, #calls("pop"))
    end)
  end)
end)
