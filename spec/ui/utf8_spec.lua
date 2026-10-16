local utf8 = require("loupe.ui.utf8")

-- "aé€😀" is 1 + 2 + 3 + 4 bytes: boundaries at 0, 1, 3, 6, 10.
local TEXT = "a\195\169\226\130\172\240\159\152\128"

describe("ui.utf8", function()
  it("drops the last character, however many bytes it takes", function()
    assert.equal("a\195\169\226\130\172", utf8.dropLast(TEXT))
    assert.equal("", utf8.dropLast("a"))
    assert.equal("", utf8.dropLast(""))
  end)

  it("steps back to the previous character boundary", function()
    assert.equal(6, utf8.prev(TEXT, 10))
    assert.equal(3, utf8.prev(TEXT, 6))
    assert.equal(1, utf8.prev(TEXT, 3))
    assert.equal(0, utf8.prev(TEXT, 1))
    assert.equal(0, utf8.prev(TEXT, 0))
  end)

  it("steps forward to the next character boundary", function()
    assert.equal(1, utf8.next(TEXT, 0))
    assert.equal(3, utf8.next(TEXT, 1))
    assert.equal(6, utf8.next(TEXT, 3))
    assert.equal(10, utf8.next(TEXT, 6))
    assert.equal(10, utf8.next(TEXT, 10))
  end)
end)
