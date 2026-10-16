-- loupe's immediate-mode UI. Pure Lua: it never draws, it returns draw
-- commands for ui/render_love.lua to replay (ADR 0002).
--
--   local render = require("loupe.ui.render_love")
--   local ui = require("loupe.ui")
--   local ctx = ui.new({ measure = render.measure, lineHeight = render.lineHeight })
--   local input = ui.newInput()   -- feed it LÖVE's mouse/keyboard events
--
-- See docs/api.md ("The UI toolkit") and examples/ui_gallery for full wiring.
local context = require("loupe.ui.context")
local input = require("loupe.ui.input")

return {
  new = context.new,
  newInput = input.new,
}
