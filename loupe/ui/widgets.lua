-- Widgets, installed as methods on the UI context (see ui/context.lua).
--
-- Labels may carry a hidden id suffix: "Go##restart" shows "Go" but is told
-- apart from other "Go" buttons by "restart".
local escape = require("loupe.ui.escape")
local utf8 = require("loupe.ui.utf8")

local W = {}

local DRAG_THRESHOLD = 3 -- pixels before a press on a number becomes a drag
local FINE = 0.1 -- Shift-drag speed factor
local MAX_DECIMALS = 6 -- dragged values are rounded to at most this many

-- Returns the label as shown (on one line) and its id part.
local function splitLabel(self, label)
  local shown, id = label:match("^(.-)##(.+)$")
  if shown then
    return self:oneLine(shown), id
  end
  return self:oneLine(label), label
end

local function clamp(v, lo, hi)
  if lo and v < lo then
    v = lo
  end
  if hi and v > hi then
    v = hi
  end
  return v
end

function W.formatNumber(v)
  if v == math.floor(v) and math.abs(v) < 1e15 then
    return ("%d"):format(v)
  end
  return (("%.3f"):format(v):gsub("0+$", ""):gsub("%.$", ""))
end

-- Rounds a dragged value to one decimal finer than the drag's step per
-- pixel: 0.2 - 3 * 0.05 is 0.049999999999999989 in floating point, and
-- should be 0.05. Typed values are never rounded.
local function roundForStep(v, step)
  local places = math.ceil(-math.log(step) / math.log(10)) + 1
  places = math.max(0, math.min(MAX_DECIMALS, places))
  local m = 10 ^ places
  if math.abs(v * m) >= 2 ^ 52 then
    return v -- beyond what a double holds in decimals anyway
  end
  return math.floor(v * m + 0.5) / m
end

local function text(self, str, x, y, color, font)
  self:emit({ "text", self:oneLine(str), x, y, color, font = font })
end

-- A full-width row: label on the left, returns the value box on the right.
local function labeledRow(self, label)
  local t = self.theme
  local x, y, w, h = self:place(nil, self.rowHeight)
  local labelWidth = math.floor(w * t.labelRatio)
  text(self, self:fitText(label, labelWidth - t.space.md), x, self:textY(y), t.colors.textMuted)
  return x + labelWidth, y, w - labelWidth, h
end

-- The rounded input box behind numbers, text and colors.
local function fieldBox(self, x, y, w, h, hovered, active)
  local t, c = self.theme, self.theme.colors
  local r = t.radiusSmall
  self:emit({ "rect", x, y, w, h, (hovered or active) and c.fieldHover or c.field, radius = r })
  local border = active and c.accent or (hovered and c.borderStrong or c.border)
  self:emit({ "outline", x, y, w, h, border, radius = r, width = t.hairline })
end

-- A soft ring outside a box: shows where the keyboard goes.
local function focusRing(self, x, y, w, h)
  local t = self.theme
  local g = t.focusRing
  self:emit({
    "outline",
    x - g,
    y - g,
    w + 2 * g,
    h + 2 * g,
    t.colors.focus,
    radius = t.radiusSmall + g,
    width = g,
  })
end

-- Vector icons, drawn in a size x size box. Fonts may lack symbol glyphs
-- (LÖVE's default font does), and lines stay crisp at any UI scale.
local function icon(self, name, x, y, size, color)
  local s = size
  local lw = math.max(1.5, s / 8)
  if name == "pause" then
    local bw = math.max(2, math.floor(s * 0.22))
    local gap = math.max(2, math.floor(s * 0.2))
    local left = x + math.floor((s - 2 * bw - gap) / 2)
    self:emit({ "rect", left, y + s * 0.18, bw, s * 0.64, color, radius = 1 })
    self:emit({ "rect", left + bw + gap, y + s * 0.18, bw, s * 0.64, color, radius = 1 })
  elseif name == "play" then
    self:emit({
      "poly",
      { x + s * 0.28, y + s * 0.18, x + s * 0.82, y + s * 0.5, x + s * 0.28, y + s * 0.82 },
      color,
    })
  elseif name == "step" then
    self:emit({
      "poly",
      { x + s * 0.18, y + s * 0.2, x + s * 0.64, y + s * 0.5, x + s * 0.18, y + s * 0.8 },
      color,
    })
    self:emit({ "rect", x + s * 0.68, y + s * 0.2, math.max(2, s * 0.14), s * 0.6, color })
  elseif name == "minus" then
    self:emit({
      "line",
      { x + s * 0.25, y + s * 0.5, x + s * 0.75, y + s * 0.5 },
      color,
      width = lw,
    })
  elseif name == "plus" then
    self:emit({
      "line",
      { x + s * 0.25, y + s * 0.5, x + s * 0.75, y + s * 0.5 },
      color,
      width = lw,
    })
    self:emit({
      "line",
      { x + s * 0.5, y + s * 0.25, x + s * 0.5, y + s * 0.75 },
      color,
      width = lw,
    })
  elseif name == "chevronRight" then
    self:emit({
      "line",
      { x + s * 0.38, y + s * 0.24, x + s * 0.64, y + s * 0.5, x + s * 0.38, y + s * 0.76 },
      color,
      width = lw,
    })
  elseif name == "chevronDown" then
    self:emit({
      "line",
      { x + s * 0.24, y + s * 0.38, x + s * 0.5, y + s * 0.64, x + s * 0.76, y + s * 0.38 },
      color,
      width = lw,
    })
  elseif name == "check" then
    self:emit({
      "line",
      { x + s * 0.22, y + s * 0.52, x + s * 0.42, y + s * 0.72, x + s * 0.78, y + s * 0.3 },
      color,
      width = math.max(1.5, s / 7),
    })
  end
end

W.icon = icon

local CARET_WIDTH = 1

-- Fields edit one line of text. A string that holds newlines, tabs or other
-- control characters is edited in its escaped form ("a\nb" shows as a, \, n,
-- b) and decoded on commit, so its newlines survive an edit that doesn't
-- touch them and new ones can be typed as \n. Strings without control
-- characters edit exactly as typed: a backslash stays a backslash. Pasting
-- text with control characters switches the edit to the escaped form.
--
-- The edit (self.edit) holds text, cursor and anchor as byte offsets; the
-- selection runs between anchor and cursor.

-- The selected byte range, or nil when nothing is selected.
local function selectionRange(edit)
  local a, b = edit.anchor, edit.cursor
  if a == nil or a == b then
    return nil
  end
  return math.min(a, b), math.max(a, b)
end

-- Replaces the selection (or inserts at the cursor) with s.
local function replaceSelection(edit, s)
  local a, b = selectionRange(edit)
  a = a or edit.cursor
  b = b or edit.cursor
  edit.text = edit.text:sub(1, a) .. s .. edit.text:sub(b + 1)
  edit.cursor, edit.anchor = a + #s, nil
end

-- Moves the cursor; extend (Shift) grows the selection instead of dropping it.
local function moveTo(edit, pos, extend)
  if extend then
    edit.anchor = edit.anchor or edit.cursor
  else
    edit.anchor = nil
  end
  edit.cursor = pos
end

-- Re-expresses the edit in escaped form, keeping cursor and selection on the
-- same characters.
local function switchToEscaped(edit)
  local function at(pos)
    return pos and #escape.encode(edit.text:sub(1, pos))
  end
  edit.cursor, edit.anchor = at(edit.cursor), at(edit.anchor)
  edit.text = escape.encode(edit.text)
  edit.escaped = true
end

local function copy(self, edit)
  local a, b = selectionRange(edit)
  if not a then
    return false
  end
  local s = edit.text:sub(a + 1, b)
  self:setClipboard(edit.escaped and escape.decode(s) or s)
  return true
end

local function paste(self, edit)
  local s = self:getClipboard()
  if not edit.escaped and escape.hasControl(s) then
    switchToEscaped(edit)
  end
  replaceSelection(edit, edit.escaped and escape.encode(s) or s)
end

-- Ctrl (Cmd on macOS) shortcuts.
local function applyShortcut(self, edit, key)
  if key == "a" then
    edit.anchor, edit.cursor = 0, #edit.text
  elseif key == "c" then
    copy(self, edit)
  elseif key == "x" then
    if copy(self, edit) then
      replaceSelection(edit, "")
    end
  elseif key == "v" then
    paste(self, edit)
  end
end

-- Applies one key to the edit.
local function applyKey(edit, key, shift)
  local str, cursor = edit.text, edit.cursor
  local a, b = selectionRange(edit)
  if (key == "backspace" or key == "delete") and a then
    replaceSelection(edit, "")
  elseif key == "backspace" and cursor > 0 then
    local p = utf8.prev(str, cursor)
    edit.text, edit.cursor = str:sub(1, p) .. str:sub(cursor + 1), p
  elseif key == "delete" and cursor < #str then
    edit.text = str:sub(1, cursor) .. str:sub(utf8.next(str, cursor) + 1)
  elseif key == "left" then
    moveTo(edit, (a and not shift) and a or utf8.prev(str, cursor), shift)
  elseif key == "right" then
    moveTo(edit, (b and not shift) and b or utf8.next(str, cursor), shift)
  elseif key == "home" then
    moveTo(edit, 0, shift)
  elseif key == "end" then
    moveTo(edit, #str, shift)
  end
end

-- The character boundary nearest to px pixels right of where the view starts.
local function boundaryAt(self, str, start, px, font)
  local best, bestDist, pos = start, math.abs(px), start
  while pos < #str do
    pos = utf8.next(str, pos)
    local width = self.measure(str:sub(start + 1, pos), font)
    local dist = math.abs(width - px)
    if dist < bestDist then
      best, bestDist = pos, dist
    end
    if width > px then
      break
    end
  end
  return best
end

-- The first byte shown: moves only as far as needed to keep the cursor in
-- view, and back again when the text shrinks, so typing at the end keeps the
-- end visible.
local function scrollStart(self, str, cursor, start, avail, font)
  start = math.min(start, cursor)
  while self.measure(str:sub(start + 1, cursor), font) > avail do
    start = utf8.next(str, start)
  end
  while start > 0 and self.measure(str:sub(utf8.prev(str, start) + 1), font) <= avail do
    start = utf8.prev(str, start)
  end
  return start
end

-- Text editing for the field that has focus. Returns the text (decoded when
-- the edit was escaped), done, cancelled.
local function editText(self, x, y, w, h, font)
  local edit, input, t = self.edit, self.input, self.theme
  edit.seen = true
  local pad = t.controlPadding
  local avail = w - 2 * pad - CARET_WIDTH

  local done, cancelled = false, false
  local inside = input.x >= x and input.y >= y and input.x < x + w and input.y < y + h
  if input.pressed then
    if inside then
      -- Measured against last frame's view: that's what was clicked.
      moveTo(edit, boundaryAt(self, edit.text, edit.start, input.x - x - pad, font), false)
    else
      -- Clicking anywhere else commits, like most editors.
      done = true
    end
  end

  -- Apply typing in arrival order: "backspace, 3" differs from "3, backspace".
  for _, event in ipairs(input.typed) do
    local key = event.key
    if event.text then
      replaceSelection(edit, event.text)
    elseif key == "return" or key == "kpenter" then
      done = true
    elseif key == "escape" then
      cancelled = true
    elseif event.ctrl then
      applyShortcut(self, edit, key)
    else
      applyKey(edit, key, event.shift)
    end
  end

  local str, cursor = edit.text, edit.cursor
  local start = scrollStart(self, str, cursor, edit.start, avail, font)
  edit.start = start

  focusRing(self, x, y, w, h)
  fieldBox(self, x, y, w, h, true, true)
  local shown = str:sub(start + 1)
  while #shown > 0 and self.measure(shown, font) > avail do
    shown = utf8.dropLast(shown)
  end
  local textX, textY = x + pad, self:textY(y, font, h)
  local lineH = self:fontHeight(font)
  local a, b = selectionRange(edit)
  if a then
    local function offset(pos)
      return self.measure(str:sub(start + 1, math.max(pos, start)), font)
    end
    local left, right = offset(a), math.min(offset(b), avail)
    if right > left then
      self:emit({ "rect", textX + left, textY, right - left, lineH, t.colors.selectionText })
    end
  end
  text(self, shown, textX, textY, t.colors.text, font)
  local caretX = textX + self.measure(str:sub(start + 1, cursor), font)
  self:emit({ "rect", caretX, textY, CARET_WIDTH, lineH, t.colors.accent })

  if done or cancelled then
    self.edit = nil
  end
  return edit.escaped and escape.decode(str) or str, done and not cancelled, cancelled
end

local function startEdit(self, id, str)
  local escaped = escape.hasControl(str)
  local shown = escaped and escape.encode(str) or str
  self.edit = { id = id, text = shown, cursor = #shown, start = 0, seen = true, escaped = escaped }
end

local function editing(self, id)
  return self.edit ~= nil and self.edit.id == id
end

-- One row of text. color defaults to the theme's text color; font is a role.
function W:label(str, color, font)
  local x, y, w = self:place(nil, self.rowHeight)
  text(
    self,
    self:fitText(str, w, font),
    x,
    self:textY(y, font),
    color or self.theme.colors.text,
    font
  )
end

-- A label that keeps its end when too long ("..rocks[3]"), for paths.
function W:pathLabel(str, color, font)
  local x, y, w = self:place(nil, self.rowHeight)
  text(
    self,
    self:fitTextStart(str, w, font),
    x,
    self:textY(y, font),
    color or self.theme.colors.text,
    font
  )
end

function W:separator()
  local t = self.theme
  local x, y, w, h = self:place(nil, t.space.md)
  self:emit({ "rect", x, y + math.floor(h / 2), w, t.hairline, t.colors.border })
end

-- A thin vertical rule between groups on one row.
function W:divider()
  local t = self.theme
  local x, y, w, h = self:place(t.space.md + t.hairline, self.rowHeight)
  local inset = math.floor(h * 0.2)
  local lineX = x + math.floor(w / 2)
  self:emit({ "rect", lineX, y + inset, t.hairline, h - 2 * inset, t.colors.border })
end

-- Empty room on a row.
function W:spacer(width)
  self:place(width, self.rowHeight)
end

function W:sameLine()
  self.layout:sameLine()
end

-- The next widget, `width` wide, goes flush right on the current row.
function W:alignRight(width)
  self.layout:alignRight(width)
end

-- Width a button with this label and opts would take.
function W:buttonWidth(label, opts)
  local t = self.theme
  local shown = splitLabel(self, label)
  opts = opts or {}
  local iconSize = math.floor(self.rowHeight * 0.6)
  local w = 2 * t.controlPadding
  if shown ~= "" then
    w = w + self.measure(shown, opts.font)
  end
  if opts.icon then
    w = w + iconSize + (shown ~= "" and t.space.sm + 2 or 0)
    if shown == "" then
      w = math.max(self.rowHeight, iconSize + 2 * t.space.sm)
    end
  end
  return opts.width or w
end

-- Returns true on the frame the button is clicked.
-- opts.primary: accent colored. opts.quiet: no background until hovered.
-- opts.icon: "pause", "play", "step", "minus", "plus", "chevronRight", "chevronDown",
-- "check" (see icon above). opts.disabled. opts.selected: drawn pressed in.
-- opts.color: label color. opts.font: label font role. opts.width: fixed width.
function W:button(label, opts)
  opts = opts or {}
  local shown, idPart = splitLabel(self, label)
  local t, c = self.theme, self.theme.colors
  local w = self:buttonWidth(label, opts)
  local x, y, _, h = self:place(w, self.rowHeight)
  local id = self:id(idPart)
  local hovered, _, held, clicked
  if opts.disabled then
    hovered, held, clicked = false, false, false
    self.rectsNext[id] = not self.culled and { x = x, y = y, w = w, h = h } or nil
  else
    hovered, _, held, clicked = self:interact(id, x, y, w, h)
  end

  local fill
  if opts.primary and not opts.disabled then
    fill = (hovered or held) and c.accentHover or c.accent
  elseif held or opts.selected then
    fill = c.controlActive
  elseif hovered then
    fill = c.controlHover
  elseif not opts.quiet then
    fill = c.control
  end
  if fill then
    self:emit({ "rect", x, y, w, h, fill, radius = t.radiusSmall })
  end

  local color = opts.color or c.text
  if opts.disabled then
    color = c.textFaint
  elseif opts.primary then
    color = c.textOnAccent
  end
  local iconSize = math.floor(self.rowHeight * 0.6)
  local textWidth = shown ~= "" and self.measure(shown, opts.font) or 0
  local content = textWidth
  if opts.icon then
    content = content + iconSize + (shown ~= "" and t.space.sm + 2 or 0)
  end
  local cx = x + math.floor((w - content) / 2)
  if opts.icon then
    icon(self, opts.icon, cx, y + math.floor((h - iconSize) / 2), iconSize, color)
    cx = cx + iconSize + t.space.sm + 2
  end
  if shown ~= "" then
    text(self, shown, cx, self:textY(y, opts.font), color, opts.font)
  end
  return clicked
end

-- A row of joined buttons. items: labels (with optional "##id"); opts.icons:
-- icon names by index. Returns the index clicked this frame, or nil.
function W:segmented(items, opts)
  opts = opts or {}
  local t, c = self.theme, self.theme.colors
  local icons = opts.icons or {}
  local widths, total = {}, 0
  for i, label in ipairs(items) do
    widths[i] = self:buttonWidth(label, { icon = icons[i], font = opts.font })
    total = total + widths[i]
  end
  local x, y, _, h = self:place(total, self.rowHeight)
  self:emit({ "rect", x, y, total, h, c.control, radius = t.radiusSmall })
  local clickedIndex
  local cx = x
  for i, label in ipairs(items) do
    local shown, idPart = splitLabel(self, label)
    local w = widths[i]
    local hovered, _, held, clicked = self:interact(self:id(idPart), cx, y, w, h)
    if held or hovered then
      local inset = t.hairline * 2
      self:emit({
        "rect",
        cx + inset,
        y + inset,
        w - 2 * inset,
        h - 2 * inset,
        held and c.controlActive or c.controlHover,
        radius = t.radiusSmall - 1,
      })
    end
    if i > 1 then
      local inset = math.floor(h * 0.25)
      self:emit({ "rect", cx, y + inset, t.hairline, h - 2 * inset, c.border })
    end
    local iconSize = math.floor(self.rowHeight * 0.6)
    if icons[i] and shown == "" then
      icon(
        self,
        icons[i],
        cx + math.floor((w - iconSize) / 2),
        y + math.floor((h - iconSize) / 2),
        iconSize,
        c.text
      )
    else
      local tw = self.measure(shown, opts.font)
      text(self, shown, cx + math.floor((w - tw) / 2), self:textY(y, opts.font), c.text, opts.font)
    end
    if clicked then
      clickedIndex = i
    end
    cx = cx + w
  end
  return clickedIndex
end

local function toggleSize(self, shown)
  local t = self.theme
  local trackH = math.floor(self.rowHeight * 0.62)
  local trackW = math.floor(trackH * 1.75)
  return t.space.sm + trackW + t.space.md + self.measure(shown) + t.controlPadding, trackW, trackH
end

-- Width a toggle with this label would take.
function W:toggleWidth(label)
  return (toggleSize(self, (splitLabel(self, label))))
end

-- A pill switch with its label to the right. Returns value, changed.
function W:toggle(label, value)
  local shown, idPart = splitLabel(self, label)
  local t, c = self.theme, self.theme.colors
  local w, trackW, trackH = toggleSize(self, shown)
  local gap = t.space.md
  local x, y, _, h = self:place(w, self.rowHeight)
  local hovered, _, _, clicked = self:interact(self:id(idPart), x, y, w, h)
  local changed = false
  if clicked then
    value, changed = not value, true
  end
  if hovered then
    self:emit({ "rect", x, y, w, h, c.hover, radius = t.radiusSmall })
  end
  local tx, ty = x + t.space.sm, y + math.floor((h - trackH) / 2)
  self:emit({
    "rect",
    tx,
    ty,
    trackW,
    trackH,
    value and c.accent or c.controlActive,
    radius = trackH / 2,
  })
  local knob = trackH - 4
  local kx = value and (tx + trackW - knob - 2) or (tx + 2)
  self:emit({ "circle", kx + knob / 2, ty + trackH / 2, knob / 2, c.text })
  text(self, shown, tx + trackW + gap, self:textY(y), value and c.text or c.textMuted)
  return value, changed
end

-- Returns value, changed.
function W:checkbox(label, value)
  local shown, idPart = splitLabel(self, label)
  local t, c = self.theme, self.theme.colors
  local x, y, w, h = labeledRow(self, shown)
  local hovered, _, held, clicked = self:interact(self:id(idPart), x, y, w, h)
  local changed = false
  if clicked then
    value, changed = not value, true
  end
  local box = math.floor(h * 0.66)
  local bx, by = x, y + math.floor((h - box) / 2)
  if value then
    self:emit({ "rect", bx, by, box, box, hovered and c.accentHover or c.accent, radius = 4 })
    icon(self, "check", bx, by, box, c.textOnAccent)
  else
    fieldBox(self, bx, by, box, box, hovered, held)
  end
  text(
    self,
    value and "true" or "false",
    bx + box + t.space.md,
    self:textY(y),
    c.textFaint,
    "small"
  )
  return value, changed
end

-- Drag horizontally to change; click without dragging to type a value.
-- Integers (and opts.integer) drag in whole steps unless Shift is held
-- (input.shift); Shift also slows the drag down for fine control.
-- opts: speed (per pixel; default scales with the value), min, max, integer.
-- Returns value, changed.
function W:dragNumber(label, value, opts)
  opts = opts or {}
  local shown, idPart = splitLabel(self, label)
  local id = self:id(idPart)
  local x, y, w, h = labeledRow(self, shown)

  if editing(self, id) then
    self.rectsNext[id] = { x = x, y = y, w = w, h = h }
    local str, done = editText(self, x, y, w, h, "mono")
    local typed = done and tonumber(str)
    if typed then
      typed = clamp(typed, opts.min, opts.max)
      return typed, typed ~= value
    end
    return value, false
  end

  local input = self.input
  local hovered, pressed, held, clicked = self:interact(id, x, y, w, h)
  local changed = false
  if pressed then
    self.drag = { id = id, startX = input.x, startValue = value, moved = false }
  end
  local drag = self.drag
  if held and drag and drag.id == id then
    local dx = input.x - drag.startX
    if math.abs(dx) >= DRAG_THRESHOLD then
      drag.moved = true
    end
    if drag.moved then
      local speed = opts.speed or math.max(0.05, math.abs(drag.startValue) * 0.005)
      local fine = input.shift == true
      if fine then
        speed = speed * FINE
      end
      local next = clamp(roundForStep(drag.startValue + dx * speed, speed), opts.min, opts.max)
      local whole = opts.integer or (opts.integer == nil and drag.startValue % 1 == 0)
      if whole and not (fine and not opts.integer) then
        next = math.floor(next + 0.5)
      end
      if next ~= value then
        value, changed = next, true
      end
    end
    if clicked and not drag.moved then
      startEdit(self, id, W.formatNumber(value))
    end
  end

  local t, c = self.theme, self.theme.colors
  fieldBox(self, x, y, w, h, hovered, held)
  text(self, W.formatNumber(value), x + t.controlPadding, self:textY(y, "mono"), c.text, "mono")
  if hovered or held then
    -- Small arrows at the right edge say "drag me".
    local s = math.floor(h * 0.5)
    local iy = y + math.floor((h - s) / 2)
    local right = x + w - t.space.sm - s
    self:emit({
      "line",
      {
        right + s * 0.3,
        iy + s * 0.25,
        right + s * 0.05,
        iy + s * 0.5,
        right + s * 0.3,
        iy + s * 0.75,
      },
      c.textFaint,
      width = 1.5,
    })
    self:emit({
      "line",
      {
        right + s * 0.7,
        iy + s * 0.25,
        right + s * 0.95,
        iy + s * 0.5,
        right + s * 0.7,
        iy + s * 0.75,
      },
      c.textFaint,
      width = 1.5,
    })
  end
  return value, changed
end

-- Click to edit; enter or clicking elsewhere commits, escape cancels.
-- Returns value, changed.
function W:textField(label, value)
  local shown, idPart = splitLabel(self, label)
  local id = self:id(idPart)
  local x, y, w, h = labeledRow(self, shown)

  if editing(self, id) then
    self.rectsNext[id] = { x = x, y = y, w = w, h = h }
    local str, done = editText(self, x, y, w, h)
    if done then
      return str, str ~= value
    end
    return value, false
  end

  local t = self.theme
  local hovered, _, held, clicked = self:interact(id, x, y, w, h)
  if clicked then
    startEdit(self, id, value)
  end
  fieldBox(self, x, y, w, h, hovered, held)
  text(
    self,
    self:fitText(value, w - 2 * t.controlPadding),
    x + t.controlPadding,
    self:textY(y),
    t.colors.text
  )
  return value, false
end

-- A read-only labeled value, for things loupe can't edit (functions, cycles).
function W:valueRow(label, value)
  local t = self.theme
  local x, y, w = labeledRow(self, label)
  local pad = t.controlPadding
  text(
    self,
    self:fitText(value, w - pad, "mono"),
    x + pad,
    self:textY(y, "mono"),
    t.colors.textFaint,
    "mono"
  )
end

-- Returns open, picked. When open, the caller must call treePop() after the
-- node's children.
-- opts.open: initial state. opts.selectable: the chevron toggles and the
-- label picks (picked = true that frame). opts.selected: draw as selected.
-- opts.leaf: nothing to expand: no chevron, never open, and with selectable
-- the whole row picks. opts.count: muted text at the right (a child count).
function W:treeNode(label, opts)
  opts = opts or {}
  local shown, idPart = splitLabel(self, label)
  local id = self:id(idPart)
  local t, c = self.theme, self.theme.colors
  local x, y, w, h = self:place(nil, self.rowHeight)

  local open = self.open[id]
  if open == nil then
    open = opts.open == true
  end
  if opts.leaf then
    open = false
  end
  local hovered, _, _, clicked = self:interact(id, x, y, w, h)
  local picked = false
  if clicked then
    if opts.selectable and (opts.leaf or self.input.x >= x + t.indent) then
      picked = true
    elseif not opts.leaf then
      open = not open
    end
  end
  if not opts.leaf then
    self.open[id] = open
  end

  if opts.selected then
    self:emit({ "rect", x, y, w, h, c.selection, radius = t.radiusSmall })
  elseif hovered then
    self:emit({ "rect", x, y, w, h, c.hover, radius = t.radiusSmall })
  end
  if not opts.leaf then
    local s = t.indent
    icon(
      self,
      open and "chevronDown" or "chevronRight",
      x,
      y + math.floor((h - s) / 2),
      s,
      opts.selected and c.text or c.textMuted
    )
  end
  local labelX = x + t.indent + t.space.xs
  local right = x + w - t.space.sm - 2
  if opts.count then
    local count = self:oneLine(opts.count)
    local cw = self.measure(count, "small")
    text(
      self,
      count,
      right - cw,
      self:textY(y, "small"),
      opts.selected and c.textMuted or c.textFaint,
      "small"
    )
    right = right - cw - t.space.md
  end
  text(self, self:fitText(shown, right - labelX), labelX, self:textY(y), c.text)

  if open then
    self:pushId(idPart)
    self.layout:indent(t.indent)
  end
  return open, picked
end

function W:treePop()
  self.layout:unindent(self.theme.indent)
  self:popId()
end

local function hex(color)
  local function byte(v)
    return math.floor(clamp(v or 1, 0, 1) * 255 + 0.5)
  end
  return ("#%02X%02X%02X"):format(byte(color[1]), byte(color[2]), byte(color[3]))
end

-- Shows a color; returns true when clicked.
function W:colorSwatch(label, color)
  local shown, idPart = splitLabel(self, label)
  local t, c = self.theme, self.theme.colors
  local x, y, w, h = labeledRow(self, shown)
  local hovered, _, held, clicked = self:interact(self:id(idPart), x, y, w, h)
  fieldBox(self, x, y, w, h, hovered, held)
  local inset = 4
  local sw = math.min(w - 2 * inset, math.floor(h * 1.4))
  self:emit({ "rect", x + inset, y + inset, sw, h - 2 * inset, color, radius = 3 })
  self:emit({ "outline", x + inset, y + inset, sw, h - 2 * inset, c.borderStrong, radius = 3 })
  local desc = hex(color)
  if color[4] and color[4] < 1 then
    desc = desc .. ("  %d%%"):format(math.floor(color[4] * 100 + 0.5))
  end
  local tx = x + inset + sw + t.space.md
  text(
    self,
    self:fitText(desc, x + w - tx - inset, "mono"),
    tx,
    self:textY(y, "mono"),
    c.textMuted,
    "mono"
  )
  return clicked
end

return W
