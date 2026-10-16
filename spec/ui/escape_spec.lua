local escape = require("loupe.ui.escape")

local ARROW = "\226\134\181" -- "↵"

describe("ui.escape", function()
  it("knows whether a string has control characters", function()
    assert.is_true(escape.hasControl("a\nb"))
    assert.is_true(escape.hasControl("\0"))
    assert.is_true(escape.hasControl("\127"))
    assert.is_false(escape.hasControl("caf\195\169 \\n"))
  end)

  describe("oneLine", function()
    it("leaves ordinary text alone, multi-byte characters included", function()
      local s = "caf\195\169 \\n"
      assert.equal(s, escape.oneLine(s))
    end)

    it("shows newlines, tabs and other control characters as escapes by default", function()
      assert.equal("a\\nb\\tc\\rd\\000e\\027", escape.oneLine("a\nb\tc\rd\0e\27"))
    end)

    it("uses the given glyphs for newlines and tabs", function()
      local glyphs = { newline = ARROW, tab = "  " }
      assert.equal("a" .. ARROW .. "b  c\\r", escape.oneLine("a\nb\tc\r", glyphs))
    end)

    it("never returns more than one line", function()
      assert.is_nil(escape.oneLine("\n\r\n\t\v\f"):find("%c"))
    end)
  end)

  describe("encode and decode", function()
    local cases = {
      "",
      "plain",
      "two\nlines",
      "tab\there",
      "crlf\r\n",
      "back\\slash",
      "literal \\n stays literal",
      "\0\1\31\127",
      "caf\195\169\n",
    }

    it("encodes to one line of printable text", function()
      for _, s in ipairs(cases) do
        assert.is_nil(escape.encode(s):find("%c"), s)
      end
      assert.equal("a\\nb\\tc\\rd\\\\e\\000", escape.encode("a\nb\tc\rd\\e\0"))
    end)

    it("round-trips every string exactly", function()
      for _, s in ipairs(cases) do
        assert.equal(s, escape.decode(escape.encode(s)))
      end
    end)

    it("decodes what a person would type", function()
      assert.equal("a\nb", escape.decode("a\\nb"))
      assert.equal("x\ty", escape.decode("x\\ty"))
      assert.equal("\\", escape.decode("\\\\"))
      assert.equal("A", escape.decode("\\065"))
      assert.equal("\0" .. "1", escape.decode("\\0001"))
    end)

    it("keeps backslashes that start no escape", function()
      assert.equal("\\q", escape.decode("\\q"))
      assert.equal("end\\", escape.decode("end\\"))
      assert.equal("\\999", escape.decode("\\999"))
    end)
  end)
end)
