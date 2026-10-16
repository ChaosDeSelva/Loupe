describe("window presets", function()
  local window, previous, calls, fullscreen
  before_each(function()
    previous = rawget(_G, "love")
    calls, fullscreen = {}, false
    love = {
      window = {
        getMode = function()
          return 1440, 900, { vsync = 1, msaa = 4 }
        end,
        getFullscreen = function()
          return fullscreen
        end,
        setFullscreen = function(value, kind)
          fullscreen = value
          calls[#calls + 1] = { value, kind }
          return true
        end,
        setMode = function(w, h, flags)
          calls[#calls + 1] = { w, h, flags }
          return true
        end,
      },
    }
    rawset(_G, "love", love)
    package.loaded["loupe.window"] = nil
    window = require("loupe.window")
  end)
  after_each(function()
    rawset(_G, "love", previous)
  end)
  it("uses desktop fullscreen and restores windowed mode", function()
    assert.is_true(window.toggleFullscreen())
    assert.same({ true, "desktop" }, calls[1])
    window.toggleFullscreen()
    assert.same({ false, "desktop" }, calls[2])
  end)
  it("preserves rendering flags while enabling DPI and resizing", function()
    window.setSize(1280, 800)
    assert.same(
      { 1280, 800, { vsync = 1, msaa = 4, fullscreen = false, resizable = true, highdpi = true } },
      calls[1]
    )
  end)
  it("rejects invalid dimensions", function()
    assert.has_error(function()
      window.setSize(0, 900)
    end)
  end)
end)
