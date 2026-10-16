local history = require("loupe.core.history")

describe("core.history", function()
  local h, t
  before_each(function()
    h = history.new()
    t = { x = 0, y = 0 }
  end)

  local function set(key, value, gesture)
    local old = t[key]
    t[key] = value
    h:record({ target = t, key = key, old = old, new = value, gesture = gesture })
  end

  it("undoes and redoes a change", function()
    set("x", 5, 1)
    assert.is_true(h:canUndo())
    h:undo()
    assert.equal(0, t.x)
    assert.is_true(h:canRedo())
    h:redo()
    assert.equal(5, t.x)
  end)

  it("does nothing when there is nothing to undo or redo", function()
    assert.is_nil(h:undo())
    assert.is_nil(h:redo())
  end)

  it("merges changes from the same gesture into one step", function()
    set("x", 1, 7)
    set("x", 2, 7)
    set("y", 3, 7)
    set("x", 4, 7)
    h:undo()
    assert.same({ 0, 0 }, { t.x, t.y })
    assert.is_false(h:canUndo())
    h:redo()
    assert.same({ 4, 3 }, { t.x, t.y })
  end)

  it("starts a new step for a new gesture", function()
    set("x", 1, 1)
    set("x", 2, 2)
    h:undo()
    assert.equal(1, t.x)
  end)

  it("never merges changes without a gesture", function()
    set("x", 1)
    set("x", 2)
    h:undo()
    assert.equal(1, t.x)
  end)

  it("doesn't merge into a step after undo/redo", function()
    set("x", 1, 1)
    set("x", 2, 2)
    h:undo()
    h:redo()
    set("x", 3, 2) -- same gesture id as the redone step
    h:undo()
    assert.equal(2, t.x)
  end)

  it("drops the redo list when a new change is made", function()
    set("x", 1, 1)
    h:undo()
    set("y", 1, 2)
    assert.is_false(h:canRedo())
  end)

  it("ignores changes that don't change anything", function()
    h:record({ target = t, key = "x", old = 0, new = 0, gesture = 1 })
    assert.is_false(h:canUndo())
  end)

  it("returns the step it undid or redid", function()
    set("x", 1, 1)
    local step = h:undo()
    assert.equal("x", step.changes[1].key)
    assert.equal(step, h:redo())
  end)

  it("keeps at most `limit` steps", function()
    h = history.new({ limit = 3 })
    for i = 1, 5 do
      set("x", i, i)
    end
    local undone = 0
    while h:undo() do
      undone = undone + 1
    end
    assert.equal(3, undone)
    assert.equal(2, t.x)
  end)

  it("counts revisions so callers can tell when anything changed", function()
    local r0 = h.revision
    set("x", 1, 1)
    set("x", 2, 1) -- merged, but still a change
    assert.equal(r0 + 2, h.revision)
    h:undo()
    assert.equal(r0 + 3, h.revision)
  end)
end)
