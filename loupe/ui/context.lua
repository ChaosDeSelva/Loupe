-- The immediate-mode UI context: windows, ids, hit-testing and draw commands.
--
-- Each frame: ctx:beginFrame(inputSnapshot, screenW, screenH), build windows
-- and widgets, then ctx:endFrame() returns the draw commands (see ADR 0002).
-- The only state kept between frames is window placement, which widget is
-- held (active), the text being edited, which tree nodes are open, and the
-- rects widgets had last frame (ctx:rectOf, for hit-testing tools and specs).
local layout = require("loupe.ui.layout")
local escape = require("loupe.ui.escape")
local themes = require("loupe.ui.theme")
local utf8 = require("loupe.ui.utf8")

local M = {}

local Context = {}
Context.__index = Context

local function inRect(px, py, x, y, w, h)
  return px >= x and py >= y and px < x + w and py < y + h
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local AUTO_CLIP = 100000 -- clip height for auto-height windows: no vertical clipping

-- opts.measure(text, font) -> width in pixels (required). font is a theme
--   font role ("body", "small", "title", "mono", "strong"); nil means body.
-- opts.lineHeight: font height in pixels, or function(font) -> height.
-- opts.theme: a full theme (see ui/theme.lua; build one with theme.build).
-- opts.clipboard = { get = fn() -> string, set = fn(string) }: the system
--   clipboard for copy, cut and paste in fields. Without it, fields share a
--   clipboard of their own.
function M.new(opts)
  assert(opts and opts.measure, "loupe.ui: opts.measure(text) is required")
  local ctx = setmetatable({
    windows = {},
    order = {}, -- back to front
    open = {}, -- tree node id -> bool
    active = nil, -- id of the widget being held
    edit = nil, -- { id, text, cursor, start, seen } while a field has keyboard focus
    drag = nil, -- dragNumber bookkeeping
    rects = {}, -- id -> { x, y, w, h } of every widget drawn last frame
    handles = {}, -- splitters drawn last frame, for hit-testing
    ellipsis = "..",
    -- What newlines and tabs look like on one line (see Context:oneLine).
    -- Empty means written-out escapes, which any font can draw.
    glyphs = {},
    clipboard = opts.clipboard,
    ownClipboard = "",
  }, Context)
  ctx:setMetrics(opts.measure, opts.lineHeight or 14)
  ctx:setTheme(opts.theme or themes.build())
  return ctx
end

-- Swap the theme (e.g. when the UI scale changes). Takes effect immediately.
function Context:setTheme(theme)
  self.theme = theme
  self.rowHeight = math.max(theme.rowHeight, self:fontHeight("body") + 4)
end

function Context:setMetrics(measure, lineHeight)
  self.measure = measure
  self.lineHeightFn = type(lineHeight) == "function" and lineHeight or nil
  self.lineHeight = self.lineHeightFn and self.lineHeightFn("body") or lineHeight
  if self.theme then
    self:setTheme(self.theme)
  end
end

function Context:fontHeight(font)
  if self.lineHeightFn then
    return self.lineHeightFn(font or "body")
  end
  return self.lineHeight
end

-- The rect a widget (or window) with this id had last frame, or nil.
function Context:rectOf(id)
  return self.rects[id]
end

-- Topmost window drawn last frame that contains the point.
function Context:windowAt(x, y)
  for i = #self.order, 1, -1 do
    local win = self.order[i]
    if win.shown and inRect(x, y, win.x, win.y, win.w, win.h) then
      return win
    end
  end
end

local function handleAt(self, x, y)
  for _, h in ipairs(self.handles) do
    if inRect(x, y, h.x, h.y, h.w, h.h) then
      return h
    end
  end
end

-- Whether a mouse event at (x, y) belongs to the UI rather than the game.
function Context:wantsMouse(x, y)
  return self.active ~= nil or handleAt(self, x, y) ~= nil or self:windowAt(x, y) ~= nil
end

function Context:wantsKeyboard()
  return self.edit ~= nil
end

function Context:bringToFront(win)
  if win.docked then
    return
  end
  for i, w in ipairs(self.order) do
    if w == win then
      table.remove(self.order, i)
      break
    end
  end
  self.order[#self.order + 1] = win
end

-- screenW, screenH: optional; floating windows are kept on screen within them.
function Context:beginFrame(input, screenW, screenH)
  self.input = input
  self.screenW, self.screenH = screenW, screenH
  self.hotNext = nil
  self.rectsNext = {}
  self.handlesNext = {}
  self.overlay = {}
  -- Splitters sit on window edges and win over the windows they divide.
  self.hoveredHandle = handleAt(self, input.x, input.y)
  self.hoveredWindow = not self.hoveredHandle and self:windowAt(input.x, input.y) or nil
  if input.pressed and self.hoveredWindow then
    self:bringToFront(self.hoveredWindow)
  end
  for _, win in ipairs(self.order) do
    win.shownNow = false
  end
end

function Context:endFrame()
  if self.input.released then
    self.active, self.drag = nil, nil
  end
  self.hot = self.hotNext
  self.rects = self.rectsNext
  self.handles = self.handlesNext

  -- A field that wasn't drawn this frame can't keep focus.
  if self.edit then
    if self.edit.seen then
      self.edit.seen = false
    else
      self.edit = nil
    end
  end

  local out = {}
  for _, win in ipairs(self.order) do
    win.shown = win.shownNow
    if win.shown then
      for _, cmd in ipairs(win.commands) do
        out[#out + 1] = cmd
      end
    end
  end
  for _, cmd in ipairs(self.overlay) do
    out[#out + 1] = cmd
  end
  self.input = nil
  return out
end

-- Keeps a floating window's title bar reachable: never above the screen,
-- never fully off any edge, even after the window shrinks.
local function keepOnScreen(self, win)
  local sw, sh = self.screenW, self.screenH
  if not sw then
    return
  end
  local titleHeight = self.theme.titleHeight
  win.x = clamp(win.x, math.min(0, sw - win.w), math.max(0, sw - win.w))
  win.y = clamp(win.y, 0, math.max(0, sh - titleHeight))
end

local function emitChrome(self, win, title, rect)
  local t, c = self.theme, self.theme.colors
  local x, y, w, h = win.x, win.y, win.w, win.h
  local hair = t.hairline
  if win.chrome == "panel" then
    self:emit({ "rect", x, y, w, h, rect.surface or c.surface, windowHeight = 0 })
    local edges = rect.edges or {}
    if edges.top then
      self:emit({ "rect", x, y, w, hair, c.border })
    end
    if edges.bottom then
      self:emit({ "rect", x, y + h - hair, w, hair, c.border })
    end
    if edges.left then
      self:emit({ "rect", x, y, hair, h, c.border })
    end
    if edges.right then
      self:emit({ "rect", x + w - hair, y, hair, h, c.border })
    end
  else
    -- windowHeight marks commands endWindow resizes for auto-height windows.
    local r = t.radius
    self:emit({
      "rect",
      x,
      y + 2 * hair,
      w,
      h + 2 * hair,
      c.shadow,
      radius = r + 2,
      windowHeight = 2 * hair,
    })
    self:emit({ "rect", x, y, w, h, c.surfaceRaised, radius = r, windowHeight = 0 })
    self:emit({ "outline", x, y, w, h, c.border, radius = r, windowHeight = 0 })
  end

  if win.headerHeight == 0 then
    return
  end
  local padding = win.padding
  local right = rect.headerRight and self:oneLine(rect.headerRight)
  local rightWidth = right and (self.measure(right, "small") + t.space.md) or 0
  if win.chrome == "window" then
    local text = self:fitText(title, w - 2 * padding - rightWidth, "strong")
    self:emit({
      "text",
      text,
      x + padding,
      self:textY(y, "strong", win.headerHeight),
      c.text,
      font = "strong",
    })
    self:emit({ "rect", x, y + win.headerHeight - hair, w, hair, c.border })
  else
    local text = self:fitText(title:upper(), w - 2 * padding - rightWidth, "title")
    self:emit({
      "text",
      text,
      x + padding,
      self:textY(y, "title", win.headerHeight),
      c.textMuted,
      font = "title",
    })
  end
  if right then
    self:emit({
      "text",
      right,
      x + w - padding - self.measure(right, "small"),
      self:textY(y, "small", win.headerHeight),
      c.textFaint,
      font = "small",
    })
  end
end

-- rect = { x, y, w, h, ... }.
-- Floating windows (the default) use the rect only the first time an id is
-- seen; after that they keep their own (possibly dragged) position. They drag
-- by the title bar, come to the front when clicked, and stay on screen.
-- Options:
--   autoHeight: the window grows to fit its content.
--   docked: the rect is applied every frame (layouts that follow the
--     screen); no title drag, never brought to front. Draws as a flat panel
--     with an uppercase section header (header = false hides it).
--   popover: like docked, but drawn as a raised card.
--   headerRight: muted text at the right of the header (a count).
--   edges = { top, right, bottom, left }: hairlines on a docked panel's edges.
--   padding, padY: inner padding (horizontal, vertical); spacing: row gap.
--   surface: background color override.
function Context:beginWindow(id, title, rect)
  assert(not self.win, "loupe.ui: beginWindow called inside another window")
  local t = self.theme
  local win = self.windows[id]
  local docked = rect.docked or rect.popover
  if not win then
    win = { id = id, x = rect.x, y = rect.y, w = rect.w, h = rect.h, scroll = 0, contentHeight = 0 }
    self.windows[id] = win
    self.order[#self.order + 1] = win
  end
  if docked then
    -- An auto-height docked window keeps the height it grew to last frame.
    win.x, win.y, win.w = rect.x, rect.y, rect.w
    win.h = rect.autoHeight and win.fitHeight or rect.h
  end
  win.docked = docked
  win.autoHeight = rect.autoHeight
  win.chrome = rect.popover and "popover" or (rect.docked and "panel" or "window")
  win.padding = rect.padding or t.padding
  local padY = rect.padY or win.padding
  if title == nil or rect.header == false then
    win.headerHeight = 0
  else
    win.headerHeight = win.chrome == "window" and t.titleHeight or t.headerHeight
  end
  win.shownNow = true
  win.commands = {}
  self.win = win
  self.culled = false
  self.idStack = { id }

  local input = self.input
  local hovered = self.hoveredWindow == win

  local titleId = id .. "#title"
  if not docked then
    if hovered and input.pressed and not self.active then
      if inRect(input.x, input.y, win.x, win.y, win.w, win.headerHeight) then
        self.active = titleId
        win.grabX, win.grabY = input.x - win.x, input.y - win.y
      end
    end
    if self.active == titleId then
      win.x, win.y = input.x - win.grabX, input.y - win.grabY
    end
    keepOnScreen(self, win)
  end

  local top = win.headerHeight > 0 and win.headerHeight or padY
  local viewHeight = math.max(0, win.h - top - padY)
  if hovered and input.wheel ~= 0 then
    win.scroll = win.scroll - input.wheel * self.rowHeight * t.scrollRows
  end
  win.scroll = clamp(win.scroll, 0, math.max(0, win.contentHeight - viewHeight))

  self.rectsNext[id] = { x = win.x, y = win.y, w = win.w, h = win.h }
  emitChrome(self, win, title or "", rect)

  win.top, win.padY = top, padY
  -- Content that overflowed last frame leaves a gutter for the scrollbar.
  local gutter = 0
  if not win.autoHeight and win.contentHeight > viewHeight then
    gutter = t.scrollbarWidth + t.space.sm
  end
  win.content = {
    x = win.x + win.padding,
    y = win.y + top,
    w = math.max(0, win.w - 2 * win.padding - gutter),
    h = viewHeight,
  }
  -- The clip leaves room for focus rings around widgets at the content edge.
  -- Auto-height windows grow to fit, so they never clip vertically.
  local ring = t.focusRing + t.hairline
  self:emit({
    "clip",
    win.content.x - ring,
    win.content.y - ring,
    win.content.w + 2 * ring,
    win.autoHeight and AUTO_CLIP or (win.content.h + 2 * ring),
  })
  self.layout =
    layout.new(win.content.x, win.content.y - win.scroll, win.content.w, rect.spacing or t.spacing)
end

-- A thin, rounded scrollbar shown only when the content overflows. The thumb
-- can be dragged; the wheel scrolls anywhere over the window.
local function scrollbar(self, win)
  local t, c, input = self.theme, self.theme.colors, self.input
  local view, total = win.content.h, win.contentHeight
  if win.autoHeight or total <= view or view <= 0 then
    return
  end
  local id = win.id .. "#scrollbar"
  local width = t.scrollbarWidth
  local trackX = win.x + win.w - width - math.max(2, math.floor((win.padding - width) / 2))
  local trackY = win.content.y
  local thumb = math.max(math.floor(2 * self.rowHeight), view * view / total)
  local range = total - view
  local thumbY = trackY + (view - thumb) * (win.scroll / range)

  -- A generous grab area: the visible bar is only a few pixels wide.
  local grabX, grabW = trackX - width, 3 * width
  local over = self.hoveredWindow == win and inRect(input.x, input.y, grabX, trackY, grabW, view)
  if over and input.pressed and self.active == nil then
    self.active = id
    local onThumb = input.y >= thumbY and input.y < thumbY + thumb
    win.grab = onThumb and (input.y - thumbY) or thumb / 2
  end
  local held = self.active == id
  if held then
    local pos = clamp((input.y - win.grab - trackY) / math.max(1, view - thumb), 0, 1)
    win.scroll = pos * range
    thumbY = trackY + (view - thumb) * pos
  end
  if over then
    self.hotNext = id
  end
  self:emit({
    "rect",
    trackX,
    thumbY,
    width,
    thumb,
    (held or over) and c.scrollbarHot or c.scrollbar,
    radius = width / 2,
  })
end

function Context:endWindow()
  local win, t = self.win, self.theme
  assert(win, "loupe.ui: endWindow without beginWindow")
  win.contentHeight = self.layout:height()
  self.culled = false
  self:emit({ "unclip" })

  if win.autoHeight then
    win.h = win.top + win.contentHeight + win.padY
    win.fitHeight = win.h
    -- The chrome was drawn at last frame's height: fix it up in place.
    for _, cmd in ipairs(win.commands) do
      if cmd.windowHeight then
        cmd[5] = win.h + cmd.windowHeight
      end
    end
  else
    scrollbar(self, win)
  end
  self.rectsNext[win.id].h = win.h
  self.win, self.layout = nil, nil
  return t
end

-- Commands for a widget whose row is scrolled out of view are dropped.
function Context:emit(cmd)
  assert(self.win, "loupe.ui: widgets must be inside beginWindow/endWindow")
  if self.culled then
    return
  end
  local list = self.win.commands
  list[#list + 1] = cmd
end

function Context:id(name)
  return table.concat(self.idStack, "/") .. "/" .. name
end

function Context:pushId(name)
  self.idStack[#self.idStack + 1] = name
end

function Context:popId()
  self.idStack[#self.idStack] = nil
end

-- Reserves a box in the current window's layout and remembers it. A box
-- entirely outside the view still takes its space (so scrolling and the
-- content height stay right) but draws nothing until the next place().
function Context:place(w, h)
  assert(self.layout, "loupe.ui: widgets must be inside beginWindow/endWindow")
  local x, y, pw, ph = self.layout:place(w, h)
  self.lastRect = { x = x, y = y, w = pw, h = ph }
  -- Auto-height windows grow to fit, so nothing in them is out of view.
  local win, view = self.win, self.win.content
  self.culled = not win.autoHeight and (y + ph <= view.y or y >= view.y + view.h)
  return x, y, pw, ph
end

-- Standard widget behavior for a box. Returns hovered, pressed (this frame),
-- held, clicked (released while still over it). Also records the box under
-- the id for ctx:rectOf.
function Context:interact(id, x, y, w, h)
  local input, win = self.input, self.win
  if not self.culled then
    self.rectsNext[id] = { x = x, y = y, w = w, h = h }
  end
  local hovered = self.hoveredWindow == win
    and (self.active == nil or self.active == id)
    and inRect(input.x, input.y, x, y, w, h)
    and inRect(input.x, input.y, win.content.x, win.content.y, win.content.w, win.content.h)
  if hovered then
    self.hotNext = id
  end
  local pressed = hovered and input.pressed and self.active == nil
  if pressed then
    self.active = id
  end
  local held = self.active == id
  local clicked = held and input.released and hovered
  return hovered, pressed, held, clicked
end

-- A drag handle outside any window, such as the divider between two docked
-- panels. axis "x" moves left/right, "y" up/down. Returns hovered, held and,
-- while held, where the divider's center should go (pointer minus the grab
-- offset). Splitters take the mouse ahead of the windows under them.
function Context:splitter(id, x, y, w, h, axis)
  local input, c = self.input, self.theme.colors
  local box = { x = x, y = y, w = w, h = h, id = id }
  self.handlesNext[#self.handlesNext + 1] = box
  self.rectsNext[id] = box
  local over = self.hoveredHandle ~= nil and self.hoveredHandle.id == id
  local hovered = over and (self.active == nil or self.active == id)
  local horizontal = axis == "x"
  local center = horizontal and (x + w / 2) or (y + h / 2)
  local pointer = horizontal and input.x or input.y
  if hovered and input.pressed and self.active == nil then
    self.active = id
    self.splitGrab = pointer - center
  end
  local held = self.active == id
  if hovered or held then
    self.hotNext = id
    -- A slim accent line shows what will move.
    local thick = math.max(2, self.theme.hairline * 2)
    local line
    if horizontal then
      line = { "rect", math.floor(center - thick / 2), y, thick, h, c.accent }
    else
      line = { "rect", x, math.floor(center - thick / 2), w, thick, c.accent }
    end
    if not held then
      line[6] = c.focus
    end
    self.overlay[#self.overlay + 1] = line
  end
  return hovered, held, held and (pointer - self.splitGrab) or nil
end

-- str as it should be shown in a one-row box: newlines, tabs and other
-- control characters made visible instead of breaking the line.
function Context:oneLine(str)
  return escape.oneLine(str, self.glyphs)
end

function Context:getClipboard()
  local clip = self.clipboard
  if clip then
    return clip.get() or ""
  end
  return self.ownClipboard
end

function Context:setClipboard(str)
  local clip = self.clipboard
  if clip then
    clip.set(str)
  else
    self.ownClipboard = str
  end
end

-- Top of the text for a box of height h (default: a row) in a font.
function Context:textY(y, font, h)
  return y + math.floor(((h or self.rowHeight) - self:fontHeight(font)) / 2)
end

-- Byte offsets of every character boundary in text, after the first char.
local function boundaries(text)
  local list, pos = {}, 0
  while pos < #text do
    pos = utf8.next(text, pos)
    list[#list + 1] = pos
  end
  return list
end

-- Shortens text to fit maxWidth, ending in an ellipsis. Binary search over
-- character boundaries: O(log n) measurements, so long labels stay cheap.
function Context:fitText(text, maxWidth, font)
  text = self:oneLine(text)
  local measure = self.measure
  if measure(text, font) <= maxWidth then
    return text
  end
  local dots = self.ellipsis
  local cuts = boundaries(text)
  local lo, hi = 0, #cuts - 1 -- keep cuts[i] bytes; 0 keeps nothing
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if measure(text:sub(1, cuts[mid]) .. dots, font) <= maxWidth then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return (lo > 0 and text:sub(1, cuts[lo]) or "") .. dots
end

-- Like fitText, but keeps the end ("..rocks[3].hp"): for paths, where the
-- last part matters most.
function Context:fitTextStart(text, maxWidth, font)
  text = self:oneLine(text)
  local measure = self.measure
  if measure(text, font) <= maxWidth then
    return text
  end
  local dots = self.ellipsis
  local cuts = boundaries(text)
  table.insert(cuts, 1, 0)
  -- Drop the first cuts[i] bytes; find the smallest i that fits.
  local lo, hi = 1, #cuts
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if measure(dots .. text:sub(cuts[mid] + 1), font) <= maxWidth then
      hi = mid
    else
      lo = mid + 1
    end
  end
  return dots .. text:sub(cuts[lo] + 1)
end

for name, fn in pairs(require("loupe.ui.widgets")) do
  Context[name] = fn
end

M.Context = Context

return M
