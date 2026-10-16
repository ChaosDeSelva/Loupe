local clock = require("loupe.core.clock")

describe("core.clock", function()
  local c
  before_each(function()
    c = clock.new()
  end)

  it("passes dt through unchanged by default", function()
    assert.equal(0.016, c:advance(0.016))
    assert.is_false(c.paused)
  end)

  it("scales dt", function()
    c.scale = 0.5
    assert.equal(0.008, c:advance(0.016))
  end)

  it("returns nil while paused so the game skips its update", function()
    c:togglePause()
    assert.is_nil(c:advance(0.016))
    c:togglePause()
    assert.equal(0.016, c:advance(0.016))
  end)

  describe("step", function()
    it("pauses a running clock and releases exactly one fixed step", function()
      c:step()
      assert.is_true(c.paused)
      assert.equal(c.stepSize, c:advance(0.1))
      assert.is_nil(c:advance(0.1))
    end)

    it("queues steps requested in the same frame", function()
      c:step()
      c:step()
      assert.equal(c.stepSize, c:advance(0.1))
      assert.equal(c.stepSize, c:advance(0.1))
      assert.is_nil(c:advance(0.1))
    end)

    it("ignores the time scale so a step is always predictable", function()
      c.scale = 4
      c:step()
      assert.equal(c.stepSize, c:advance(0.1))
    end)

    it("drops queued steps when resumed", function()
      c:step()
      c:togglePause()
      assert.equal(0.016, c:advance(0.016))
      c:togglePause()
      assert.is_nil(c:advance(0.016))
    end)
  end)

  describe("speed presets", function()
    it("moves to the next faster and slower preset", function()
      c:faster()
      assert.equal(2, c.scale)
      c:slower()
      c:slower()
      assert.equal(0.5, c.scale)
    end)

    it("stops at the ends of the preset list", function()
      for _ = 1, 20 do
        c:faster()
      end
      assert.equal(clock.SCALES[#clock.SCALES], c.scale)
      for _ = 1, 20 do
        c:slower()
      end
      assert.equal(clock.SCALES[1], c.scale)
    end)

    it("snaps a custom scale to the nearest preset in the requested direction", function()
      c.scale = 1.5
      c:faster()
      assert.equal(2, c.scale)
      c.scale = 1.5
      c:slower()
      assert.equal(1, c.scale)
    end)

    it("resets to normal speed", function()
      c:faster()
      c:resetScale()
      assert.equal(1, c.scale)
    end)
  end)

  it("accepts a custom step size", function()
    assert.equal(1 / 30, clock.new({ stepSize = 1 / 30 }).stepSize)
  end)
end)
