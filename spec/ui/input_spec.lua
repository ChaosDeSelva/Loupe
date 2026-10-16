local input = require("loupe.ui.input")

describe("ui.input", function()
  local i
  before_each(function()
    i = input.new()
  end)

  it("tracks the pointer", function()
    i:mousemoved(5, 6)
    local f = i:frame()
    assert.equal(5, f.x)
    assert.equal(6, f.y)
    i:setPosition(7, 8)
    assert.equal(7, i:frame().x)
  end)

  it("reports a press once, and keeps the button down until release", function()
    i:mousepressed(1, 2, 1)
    local f = i:frame()
    assert.is_true(f.pressed)
    assert.is_true(f.down)
    f = i:frame()
    assert.is_false(f.pressed)
    assert.is_true(f.down)
    i:mousereleased(1, 2, 1)
    f = i:frame()
    assert.is_true(f.released)
    assert.is_false(f.down)
  end)

  it("keeps a press and release from the same frame", function()
    i:mousepressed(1, 2, 1)
    i:mousereleased(1, 2, 1)
    local f = i:frame()
    assert.is_true(f.pressed)
    assert.is_true(f.released)
  end)

  it("ignores buttons other than the primary one", function()
    i:mousepressed(1, 2, 2)
    i:mousereleased(1, 2, 2)
    local f = i:frame()
    assert.is_false(f.pressed)
    assert.is_false(f.released)
  end)

  it("accumulates wheel and ordered typing for one frame", function()
    i:wheelmoved(0, 1)
    i:wheelmoved(0, 2)
    i:textinput("a")
    i:textinput("é")
    i:keypressed("backspace")
    i:keypressed("return")
    local f = i:frame()
    assert.equal(3, f.wheel)
    assert.same(
      { { text = "a" }, { text = "é" }, { key = "backspace" }, { key = "return" } },
      f.typed
    )

    f = i:frame()
    assert.equal(0, f.wheel)
    assert.same({}, f.typed)
  end)

  it("keeps the modifiers held with each key", function()
    i:keypressed("left", { shift = true })
    i:keypressed("v", { ctrl = true })
    i:keypressed("a", { shift = false, ctrl = false })
    assert.same(
      { { key = "left", shift = true }, { key = "v", ctrl = true }, { key = "a" } },
      i:frame().typed
    )
  end)
end)
