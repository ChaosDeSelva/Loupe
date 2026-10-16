-- Text in widgets: one-line display of control characters, escaped editing
-- of multi-line strings, selection and the clipboard, and clean drag values.
local driver = require("spec.support.ui_driver")

local frame, inWindow, at = driver.frame, driver.inWindow, driver.at
local CHAR = driver.CHAR

local ARROW = "\226\134\181" -- "↵"
local E_ACUTE = "\195\169" -- "é", two bytes

local function harness(fn, ctx)
  ctx = ctx or driver.new()
  local build = inWindow(fn)
  frame(ctx, {}, build)
  return function(fields)
    return frame(ctx, fields, build)
  end, ctx
end

-- Every text command; fails the spec if any would draw more than one line.
local function assertOneLine(cmds)
  local n = 0
  for _, cmd in ipairs(cmds) do
    if cmd[1] == "text" then
      n = n + 1
      assert.is_nil(cmd[2]:find("%c"), ("text %q spans lines"):format(cmd[2]))
    end
  end
  assert.is_true(n > 0)
end

-- Typing shorthand: "@key" presses a key, "^key" with Ctrl/Cmd, "+key" with
-- Shift; anything else is text.
local function typing(...)
  local typed = {}
  for i, k in ipairs({ ... }) do
    local mark, rest = k:sub(1, 1), k:sub(2)
    if mark == "@" then
      typed[i] = { key = rest }
    elseif mark == "^" then
      typed[i] = { key = rest, ctrl = true }
    elseif mark == "+" then
      typed[i] = { key = rest, shift = true }
    else
      typed[i] = { text = k }
    end
  end
  return { typed = typed }
end

describe("ui widgets: text", function()
  describe("one-line display", function()
    it("never draws a control character, in any widget", function()
      local s = "two\nlines\tand\rmore"
      local step = harness(function(c)
        c:label(s)
        c:pathLabel(s)
        c:valueRow(s, s)
        c:textField(s .. "##f", s)
        c:dragNumber(s .. "##n", 1)
        c:checkbox(s .. "##c", true)
        c:button(s .. "##b")
        c:toggle(s .. "##t", true)
        c:treeNode(s .. "##tree", { count = s })
        c:colorSwatch(s .. "##sw", { 1, 0, 0, 1 })
      end)
      assertOneLine(step({}))
    end)

    it("shows newlines as escapes by default, and as the context's glyph when set", function()
      local step, ctx = harness(function(c)
        c:label("a\nb")
      end)
      assert.truthy(driver.findExact(step({}), "a\\nb"))
      ctx.glyphs = { newline = ARROW }
      assert.truthy(driver.findExact(step({}), "a" .. ARROW .. "b"))
    end)

    it("fits the one-line form, not the raw text, to the width", function()
      local step, ctx = harness(function(c)
        c:label(("\n"):rep(100))
      end)
      local cmd = driver.findText(step({}), "\\n")
      assert.matches("%.%.$", cmd[2])
      assert.is_true(#cmd[2] * CHAR <= ctx.windows.w.content.w)
    end)

    it("keeps the end of a multi-line path", function()
      local step = harness(function(c)
        c:pathLabel(("x"):rep(60) .. "\nEND")
      end)
      local cmd = driver.findText(step({}), "END")
      assert.matches("^%.%..*\\nEND$", cmd[2])
    end)
  end)

  describe("editing a multi-line string", function()
    local value, changed, step, ctx

    before_each(function()
      value, changed = "a\nb", false
      step, ctx = harness(function(c)
        local ch
        value, ch = c:textField("s", value)
        changed = changed or ch
      end)
      step(driver.click(at(ctx, "s")))
    end)

    it("edits the escaped form on one line", function()
      local cmds = step({})
      assert.truthy(driver.findExact(cmds, "a\\nb"))
      assertOneLine(cmds)
    end)

    it("keeps its newlines when committed unedited", function()
      step({ keys = { "return" } })
      assert.equal("a\nb", value)
      assert.is_false(changed)
    end)

    it("turns typed escapes back into characters on commit", function()
      step(typing("\\", "t", "c", "\\", "\\", "@return"))
      assert.equal("a\nb\tc\\", value)
      assert.is_true(changed)
    end)

    it("leaves backslashes in strings without control characters literal", function()
      local plain = "x"
      local s, c2 = harness(function(c)
        plain = c:textField("p", plain)
      end)
      s(driver.click(at(c2, "p")))
      assert.truthy(driver.findExact(s({}), "x"))
      s(typing("\\", "n", "@return"))
      assert.equal("x\\n", plain)
    end)
  end)

  describe("selection and clipboard", function()
    local value, step, ctx, clip

    local function textX()
      return driver.rect(ctx, "name").x + ctx.theme.controlPadding
    end

    before_each(function()
      value = "caf" .. E_ACUTE
      clip = { text = "" }
      ctx = driver.new({
        clipboard = {
          get = function()
            return clip.text
          end,
          set = function(s)
            clip.text = s
          end,
        },
      })
      step = harness(function(c)
        value = c:textField("name", value)
      end, ctx)
      step(driver.click(at(ctx, "name")))
    end)

    it("extends a selection with Shift+Left and replaces it when typing", function()
      step(typing("+left", "+left", "Z", "@return"))
      assert.equal("caZ", value)
    end)

    it("selects to the start with Shift+Home, and deletes the selection", function()
      step(typing("@left", "+home", "@delete", "@return"))
      assert.equal(E_ACUTE, value)
    end)

    it("selects to the end with Shift+End, and backspaces the selection", function()
      step(typing("@home", "@right", "+end", "@backspace", "@return"))
      assert.equal("c", value)
    end)

    it("shrinks a selection with Shift+Right", function()
      step(typing("@home", "+end", "+left", "@backspace", "@return"))
      assert.equal(E_ACUTE, value)
    end)

    it("selects everything with Ctrl/Cmd+A", function()
      step(typing("^a", "new", "@return"))
      assert.equal("new", value)
    end)

    it("collapses a selection to its start on Left and its end on Right", function()
      step(typing("+left", "+left", "@left", "X"))
      step(typing("+right", "@right", "Y", "@return"))
      assert.equal("caXfY" .. E_ACUTE, value)
    end)

    it("drops the selection on Home and End without Shift", function()
      step(typing("^a", "@end", "!", "@return"))
      assert.equal("caf" .. E_ACUTE .. "!", value)
    end)

    it("highlights the selection behind the text", function()
      local cmds = step(typing("+left", "+left"))
      local hl = driver.findColor(cmds, "rect", ctx.theme.colors.selectionText)
      assert.truthy(hl)
      assert.equal(textX() + 2 * CHAR, hl[2])
      assert.equal(3 * CHAR, hl[4]) -- "f" and the two-byte "é"
      assert.is_nil(
        driver.findColor(step(typing("@right")), "rect", ctx.theme.colors.selectionText)
      )
    end)

    it("copies the selection with Ctrl/Cmd+C", function()
      step(typing("+left", "+left", "^c"))
      assert.equal("f" .. E_ACUTE, clip.text)
      step({ keys = { "return" } })
      assert.equal("caf" .. E_ACUTE, value)
    end)

    it("copies nothing when nothing is selected", function()
      clip.text = "kept"
      step(typing("^c"))
      assert.equal("kept", clip.text)
    end)

    it("cuts the selection with Ctrl/Cmd+X", function()
      step(typing("@home", "+right", "^x", "@return"))
      assert.equal("c", clip.text)
      assert.equal("af" .. E_ACUTE, value)
    end)

    it("pastes at the cursor with Ctrl/Cmd+V, replacing a selection", function()
      clip.text = "XY"
      step(typing("+left", "^v", "@return"))
      assert.equal("cafXY", value)
    end)

    it("pastes multi-line text as escapes, keeping its newlines on commit", function()
      clip.text = "1\n\\2"
      local cmds = step(typing("^v"))
      assert.truthy(driver.findExact(cmds, "caf" .. E_ACUTE .. "1\\n\\\\2"))
      assertOneLine(cmds)
      step({ keys = { "return" } })
      assert.equal("caf" .. E_ACUTE .. "1\n\\2", value)
    end)

    it("copies the real characters out of an escaped edit", function()
      clip.text = "a\nb"
      step(typing("^a", "^v", "^a", "^c"))
      assert.equal("a\nb", clip.text)
    end)

    it("ignores other Ctrl/Cmd keys", function()
      step(typing("^q", "@return"))
      assert.equal("caf" .. E_ACUTE, value)
    end)

    it("keeps a clipboard of its own when none is given", function()
      local v = "abc"
      local s, c2 = harness(function(c)
        v = c:textField("t", v)
      end)
      s(driver.click(at(c2, "t")))
      s(typing("^a", "^c", "@end", "^v", "@return"))
      assert.equal("abcabc", v)
    end)
  end)

  describe("typing into a number", function()
    local value, step, ctx, clip

    before_each(function()
      value, clip = 10, "12\n"
      ctx = driver.new({
        clipboard = {
          get = function()
            return clip
          end,
          set = function(s)
            clip = s
          end,
        },
      })
      step = harness(function(c)
        value = c:dragNumber("n", value)
      end, ctx)
      step(driver.click(at(ctx, "n")))
    end)

    it("selects all and replaces it", function()
      step(typing("^a", "5", "@return"))
      assert.equal(5, value)
    end)

    it("pastes a number copied with a trailing newline", function()
      step(typing("^a", "^v", "@return"))
      assert.equal(12, value)
    end)

    it("keeps a typed value exactly as typed", function()
      step(typing("^a", "0.1234567", "@return"))
      assert.equal(0.1234567, value)
    end)
  end)

  describe("dragging a number", function()
    local value, opts, step, ctx, x0, y

    before_each(function()
      value, opts = 0.2, {}
      step, ctx = harness(function(c)
        value = c:dragNumber("n", value, opts)
      end)
      x0, y = at(ctx, "n", 10)
    end)

    it("rounds to the precision the drag speed allows", function()
      -- 0.2 - 3 * 0.05 is 0.049999999999999989 in floating point.
      step(driver.press(x0, y))
      step(driver.hold(x0 - 3, y))
      assert.equal(0.05, value)
      step(driver.hold(x0 + 8, y)) -- 0.60000000000000009 unrounded
      assert.equal(0.6, value)
    end)

    it("keeps one more decimal than the step, so slow drags still move", function()
      opts.speed = 0.003
      step(driver.press(x0, y))
      step(driver.hold(x0 + 7, y)) -- 0.2 + 0.021
      assert.equal(0.221, value)
    end)

    it("rounds finer while Shift slows the drag", function()
      opts.speed = 0.01
      step(driver.press(x0, y))
      step({ x = x0 + 3, y = y, down = true, shift = true }) -- 0.2 + 0.003
      assert.equal(0.203, value)
    end)

    it("never keeps more than six decimals", function()
      opts.speed = 1e-9
      value = 0.5
      step(driver.press(x0, y))
      step(driver.hold(x0 + 3400, y)) -- 0.5000034
      assert.equal(0.500003, value)
    end)

    it("leaves large steps on whole numbers of their own size", function()
      opts.speed, opts.integer = 2.5, false
      value = 1
      step(driver.press(x0, y))
      step(driver.hold(x0 + 3, y))
      assert.equal(8.5, value)
    end)
  end)
end)
