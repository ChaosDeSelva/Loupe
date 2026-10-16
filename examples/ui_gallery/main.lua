-- Every loupe.ui widget, used directly without the rest of loupe. Doubles as
-- an example of wiring the toolkit into LÖVE by hand.
local repo = love.filesystem.getSource() .. "/../../"
package.path = repo .. "?.lua;" .. repo .. "?/init.lua;" .. package.path

local render = require("loupe.ui.render_love")
local ui = require("loupe.ui")

local ctx, input
local smokeFramesLeft

-- The values the widgets edit.
local demo = {
  clicks = 0,
  enabled = true,
  speed = 220,
  lives = 3,
  name = "Fjord ranger",
  note = "two\nlines", -- edited as "two\\nlines", committed with its newline
  tint = { 0.36, 0.62, 1, 1 },
}

local function widgetsWindow()
  ctx:beginWindow("widgets", "Widgets", { x = 20, y = 20, w = 360, h = 440 })

  ctx:label("Drag a window by its title. Wheel scrolls.", ctx.theme.colors.textMuted)
  ctx:separator()

  if ctx:button("Click me", { primary = true }) then
    demo.clicks = demo.clicks + 1
  end
  ctx:sameLine()
  if ctx:button("Reset##clicks") then
    demo.clicks = 0
  end
  ctx:sameLine()
  ctx:label(("clicked %d times"):format(demo.clicks))

  if ctx:button("Play##icon", { icon = "play" }) then
    demo.clicks = demo.clicks + 1
  end
  ctx:sameLine()
  local seg = ctx:segmented(
    { "##less", "count##count", "##more" },
    { icons = { "minus", nil, "plus" } }
  )
  if seg == 1 then
    demo.clicks = demo.clicks - 1
  elseif seg == 3 then
    demo.clicks = demo.clicks + 1
  end
  ctx:sameLine()
  demo.enabled = ctx:toggle("switch##toggle", demo.enabled)

  demo.enabled = ctx:checkbox("enabled", demo.enabled)
  demo.speed = ctx:dragNumber("speed", demo.speed)
  demo.lives = ctx:dragNumber("lives (0-9)", demo.lives, { min = 0, max = 9, integer = true })
  demo.name = ctx:textField("name", demo.name)
  demo.note = ctx:textField("note", demo.note)

  if ctx:treeNode("tint (r, g, b, a)") then
    ctx:colorSwatch("preview", demo.tint)
    for i, channel in ipairs({ "r", "g", "b", "a" }) do
      demo.tint[i] = ctx:dragNumber(channel, demo.tint[i], { min = 0, max = 1, speed = 0.005 })
    end
    ctx:treePop()
  end

  if ctx:treeNode("nested##outer", { open = true, count = "1" }) then
    if ctx:treeNode("deeper", { count = "1" }) then
      ctx:label("indented twice")
      ctx:treePop()
    end
    ctx:treePop()
  end

  ctx:endWindow()
end

local function scrollWindow()
  ctx:beginWindow("scroll", "Scrolling (50 rows)", { x = 400, y = 20, w = 260, h = 220 })
  for i = 1, 50 do
    ctx:label(("row %02d"):format(i), i % 5 == 0 and ctx.theme.colors.accent or nil)
  end
  ctx:endWindow()
end

local function stateWindow()
  ctx:beginWindow(
    "state",
    "Current values",
    { x = 400, y = 270, w = 260, h = 0, autoHeight = true }
  )
  ctx:label(("enabled = %s"):format(tostring(demo.enabled)))
  ctx:label(("speed = %s"):format(demo.speed))
  ctx:label(("lives = %d"):format(demo.lives))
  ctx:label(("name = %q"):format(demo.name))
  ctx:label(("keyboard focus: %s"):format(tostring(ctx:wantsKeyboard())))
  ctx:endWindow()
end

function love.load(args)
  for i, a in ipairs(args) do
    if a == "--smoke" then
      smokeFramesLeft = tonumber(args[i + 1]) or 120
    end
  end
  -- Fonts follow the theme's roles; measure and lineHeight take a role too.
  local theme = require("loupe.ui.theme").build()
  render.configure(theme)
  ctx = ui.new({
    measure = render.measure,
    lineHeight = render.lineHeight,
    theme = theme,
    -- Copy, cut and paste in fields use the system clipboard.
    clipboard = { get = love.system.getClipboardText, set = love.system.setClipboardText },
  })
  -- Newlines in strings show as a return arrow when the font has one.
  if render.font("body"):hasGlyphs("↵") then
    ctx.glyphs = { newline = "↵" }
  end
  input = ui.newInput()
  -- Only once: mouse events keep it current from here (see love.mousemoved).
  input:setPosition(love.mouse.getPosition())
  love.keyboard.setKeyRepeat(true)
end

function love.update()
  if smokeFramesLeft then
    smokeFramesLeft = smokeFramesLeft - 1
    if smokeFramesLeft <= 0 then
      love.event.quit(0)
    end
  end
end

function love.draw()
  love.graphics.clear(0.2, 0.22, 0.26)
  love.graphics.setColor(demo.tint)
  love.graphics.circle("fill", 820, 520, 60)

  -- Passing the screen size keeps windows' title bars on screen.
  local snapshot = input:frame()
  -- Held Shift makes number drags fine-grained; the snapshot doesn't poll the keyboard itself.
  snapshot.shift = love.keyboard.isDown("lshift", "rshift")
  ctx:beginFrame(snapshot, love.graphics.getWidth(), love.graphics.getHeight())
  widgetsWindow()
  scrollWindow()
  stateWindow()
  render.draw(ctx:endFrame())
end

function love.mousemoved(x, y)
  input:mousemoved(x, y)
end

function love.mousepressed(x, y, button)
  input:mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
  input:mousereleased(x, y, button)
end

function love.wheelmoved(dx, dy)
  input:wheelmoved(dx, dy)
end

function love.textinput(text)
  input:textinput(text)
end

function love.keypressed(key)
  if key == "escape" and not ctx:wantsKeyboard() then
    love.event.quit()
  end
  -- Shift extends a selection; Ctrl (Cmd on macOS) + A, C, X, V edit it.
  local kb = love.keyboard
  input:keypressed(key, {
    shift = kb.isDown("lshift", "rshift"),
    ctrl = kb.isDown("lctrl", "rctrl", "lgui", "rgui"),
  })
end
