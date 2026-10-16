-- The top bar: time controls, world picking, undo/redo/save, status, and a
-- "?" popover listing the keys. Docked full width across the top (ADR 0008).
local M = {}

M.MIN_STATUS = 140 -- narrowest status area before the bar wraps to two rows

local function speedLabel(scale)
  return ("x%g"):format(scale)
end

-- The bar's items, left to right. Each has a width so the bar can decide
-- whether one row is enough before drawing anything.
local function leftItems(ui, clock)
  local t = ui.theme
  local items = {
    {
      kind = "logo",
      w = ui.measure("Loupe", "strong") + math.floor(ui.rowHeight * 0.7) + t.space.sm,
    },
    { kind = "divider", w = t.space.md + t.hairline },
    {
      kind = "button",
      label = clock.paused and "Resume##pause" or "Pause##pause",
      opts = { icon = clock.paused and "play" or "pause", primary = clock.paused },
    },
    { kind = "button", label = "Step##step", opts = { icon = "step" } },
    { kind = "speed" },
    { kind = "chip" },
    { kind = "divider", w = t.space.md + t.hairline },
    { kind = "toggle", label = "Pick##pick" },
  }
  for _, item in ipairs(items) do
    if item.kind == "button" then
      item.w = ui:buttonWidth(item.label, item.opts)
    elseif item.kind == "speed" then
      local labels = { "##slower", speedLabel(clock.scale) .. "##reset", "##faster" }
      item.w = ui:buttonWidth(labels[1], { icon = "minus" })
        + ui:buttonWidth(labels[2])
        + ui:buttonWidth(labels[3], { icon = "plus" })
      item.labels = labels
    elseif item.kind == "chip" then
      item.text = clock.paused and "PAUSED" or "RUNNING"
      item.w = ui.measure(item.text, "title") + math.floor(ui.rowHeight * 0.75) + t.space.md
    elseif item.kind == "toggle" then
      item.w = ui:toggleWidth(item.label)
    end
  end
  return items
end

local function rightItems(ui, tools)
  local t = ui.theme
  local items = {}
  if tools.dirty then
    items[#items + 1] = {
      kind = "unsaved",
      w = ui.measure("unsaved changes", "small") + t.space.md + t.space.sm,
    }
  end
  items[#items + 1] =
    { kind = "button", label = "Undo", opts = { disabled = tools.canUndo == false } }
  items[#items + 1] =
    { kind = "button", label = "Redo", opts = { disabled = tools.canRedo == false } }
  items[#items + 1] = { kind = "button", label = "Save", opts = { primary = tools.dirty } }
  items[#items + 1] = {
    kind = "button",
    label = "?##help",
    opts = { quiet = true, selected = tools.help, width = ui.rowHeight },
  }
  for _, item in ipairs(items) do
    if item.kind == "button" then
      item.w = ui:buttonWidth(item.label, item.opts)
    end
  end
  return items
end

local function rowWidth(ui, items)
  local w = 0
  for i, item in ipairs(items) do
    w = w + item.w + (i > 1 and ui.theme.spacing or 0)
  end
  return w
end

local function barPadding(ui)
  return ui.theme.space.lg
end

-- Whether everything fits on one row at this width.
local function oneRow(ui, width, clock, tools)
  local inner = width - 2 * barPadding(ui)
  local needed = rowWidth(ui, leftItems(ui, clock))
    + rowWidth(ui, rightItems(ui, tools))
    + M.MIN_STATUS
    + 2 * ui.theme.space.lg
  return needed <= inner
end

-- The bar's height at this screen width: one row, or two when narrow.
function M.height(ui, screenWidth, clock, tools)
  local rows = oneRow(ui, screenWidth, clock, tools) and 1 or 2
  local t = ui.theme
  return rows * ui.rowHeight + (rows - 1) * t.spacing + 2 * t.barPadding
end

local function logo(ui)
  local t, c = ui.theme, ui.theme.colors
  local w = ui.measure("Loupe", "strong") + math.floor(ui.rowHeight * 0.7) + t.space.sm
  local x, y, _, h = ui:place(w, ui.rowHeight)
  -- A tiny lens: a ring and a handle.
  local s = math.floor(h * 0.62)
  local lx, ly = x, y + math.floor((h - s) / 2)
  local ring = math.floor(s * 0.78)
  ui:emit({ "outline", lx, ly, ring, ring, c.accent, radius = ring / 2, width = 2 })
  ui:emit({
    "line",
    { lx + ring * 0.82, ly + ring * 0.82, lx + s, ly + s },
    c.accent,
    width = 2,
  })
  ui:emit({ "text", "Loupe", x + s + t.space.sm, ui:textY(y, "strong"), c.text, font = "strong" })
end

local function chip(ui, item, clock)
  local t, c = ui.theme, ui.theme.colors
  local x, y, w, h = ui:place(item.w, ui.rowHeight)
  local color = clock.paused and c.warning or c.success
  if clock.paused then
    ui:emit({ "rect", x, y + 3, w, h - 6, c.warningSoft, radius = (h - 6) / 2 })
  end
  local dot = math.max(3, math.floor(h * 0.14))
  local dx = x + math.floor(t.space.md * 0.75) + dot
  ui:emit({ "circle", dx, y + h / 2, dot, color })
  ui:emit({
    "text",
    item.text,
    dx + dot + t.space.sm + 1,
    ui:textY(y, "title"),
    clock.paused and c.warning or c.textMuted,
    font = "title",
  })
end

local function unsaved(ui, item)
  local t, c = ui.theme, ui.theme.colors
  local x, y, _, h = ui:place(item.w, ui.rowHeight)
  local dot = math.max(3, math.floor(h * 0.12))
  ui:emit({ "circle", x + dot, y + h / 2, dot, c.warning })
  ui:emit({
    "text",
    "unsaved changes",
    x + 2 * dot + t.space.sm,
    ui:textY(y, "small"),
    c.warning,
    font = "small",
  })
end

-- Draws items; returns the action of a clicked button ("undo", "redo",
-- "save") or nil. tools.help/picking change in place.
local function drawItems(ui, items, clock, tools)
  local action
  for i, item in ipairs(items) do
    if i > 1 then
      ui:sameLine()
    end
    local kind = item.kind
    if kind == "logo" then
      logo(ui)
    elseif kind == "divider" then
      ui:divider()
    elseif kind == "chip" then
      chip(ui, item, clock)
    elseif kind == "unsaved" then
      unsaved(ui, item)
    elseif kind == "speed" then
      local clicked = ui:segmented(item.labels, { icons = { "minus", nil, "plus" } })
      if clicked == 1 then
        clock:slower()
      elseif clicked == 2 then
        clock:resetScale()
      elseif clicked == 3 then
        clock:faster()
      end
    elseif kind == "toggle" then
      tools.picking = ui:toggle(item.label, tools.picking)
    elseif ui:button(item.label, item.opts) then
      local id = item.label:match("##(.+)$") or item.label
      if id == "pause" then
        clock:togglePause()
      elseif id == "step" then
        clock:step()
      elseif id == "help" then
        tools.help = not tools.help
      else
        action = id:lower()
      end
    end
  end
  return action
end

local function status(ui, tools, width)
  local c = ui.theme.colors
  local x, y, w = ui:place(width, ui.rowHeight)
  if tools.status then
    local color = tools.statusColor or c.textMuted
    ui:emit({
      "text",
      ui:fitText(tools.status, w, "small"),
      x,
      ui:textY(y, "small"),
      color,
      font = "small",
    })
  end
end

local function keyRows(keys)
  return {
    { keys.toggle:upper(), "Show or hide loupe" },
    { keys.pause:upper(), "Pause or resume" },
    { keys.step, "Step one frame" },
    { keys.slower .. "  " .. keys.faster, "Slower, faster" },
    { keys.resetSpeed, "Normal speed" },
    { "Ctrl Z", "Undo" },
    { "Ctrl Shift Z", "Redo (also Ctrl Y)" },
    { "Ctrl S", "Save overrides" },
    { "Shift", "Hold to drag numbers finely" },
  }
end

-- Width of a key combination drawn as keycaps ("Ctrl Z" is two caps).
local function capsWidth(ui, combo)
  local t, w = ui.theme, 0
  for cap in combo:gmatch("%S+") do
    w = w + ui.measure(cap, "mono") + 2 * t.space.sm + 2 + t.space.xs * 2
  end
  return w
end

local function keycaps(ui, combo, x, y, h)
  local t, c = ui.theme, ui.theme.colors
  for cap in combo:gmatch("%S+") do
    local w = ui.measure(cap, "mono") + 2 * t.space.sm + 2
    local top, capH = y + 3, h - 6
    ui:emit({ "rect", x, top, w, capH, c.control, radius = 4 })
    ui:emit({ "rect", x + 2, top + capH - 1, w - 4, 1, c.border })
    ui:emit({ "text", cap, x + t.space.sm + 1, ui:textY(y, "mono"), c.text, font = "mono" })
    x = x + w + t.space.xs * 2
  end
end

-- A press anywhere but the popover or its button closes the popover.
local function closeHelpOnOutsideClick(ui, tools)
  local input = ui.input
  if not (tools.help and input.pressed) then
    return
  end
  for _, id in ipairs({ "loupe.help", "loupe.toolbar/help" }) do
    local r = ui:rectOf(id)
    if r and input.x >= r.x and input.y >= r.y and input.x < r.x + r.w and input.y < r.y + r.h then
      return
    end
  end
  tools.help = false
end

-- The "?" popover: every key loupe answers to.
local function help(ui, bar, keys)
  local t, c = ui.theme, ui.theme.colors
  local rows = keyRows(keys)
  local keyW = 0
  for _, r in ipairs(rows) do
    keyW = math.max(keyW, capsWidth(ui, r[1]))
  end
  local w = math.min(bar.w - 2 * t.space.md, keyW + math.floor(290 * (t.scale or 1)))
  ui:beginWindow("loupe.help", "Keyboard", {
    x = bar.x + bar.w - w - t.space.md,
    y = bar.y + bar.h + t.space.sm,
    w = w,
    h = 100,
    popover = true,
    autoHeight = true,
  })
  for _, r in ipairs(rows) do
    local x, y, rw, h = ui:place(nil, ui.rowHeight)
    keycaps(ui, r[1], x, y, h)
    local dx = x + keyW + t.space.md
    ui:emit({ "text", ui:fitText(r[2], x + rw - dx), dx, ui:textY(y), c.textMuted })
  end
  ui:separator()
  ui:label("On macOS, Cmd works in place of Ctrl.", c.textFaint, "small")
  ui:endWindow()
end

-- rect: where the bar goes (panels.layout). tools.picking and tools.help are
-- toggled in place. tools.dirty marks unsaved edits; tools.canUndo/canRedo
-- (false disables the buttons); tools.status/statusColor is the latest
-- message. Returns "undo", "redo" or "save" when one of those is clicked.
function M.build(ui, rect, clock, keys, tools)
  local t = ui.theme
  closeHelpOnOutsideClick(ui, tools)
  ui:beginWindow("loupe.toolbar", nil, {
    x = rect.x,
    y = rect.y,
    w = rect.w,
    h = rect.h,
    docked = true,
    header = false,
    padding = barPadding(ui),
    padY = t.barPadding,
    edges = { bottom = true },
  })
  local left, right = leftItems(ui, clock), rightItems(ui, tools)
  local single = oneRow(ui, rect.w, clock, tools)
  local action = drawItems(ui, left, clock, tools)
  local rightW = rowWidth(ui, right)
  local inner = rect.w - 2 * barPadding(ui)
  local statusW
  if single then
    ui:sameLine()
    ui:spacer(t.space.md)
    ui:sameLine()
    statusW = inner - rowWidth(ui, left) - rightW - 2 * t.space.md - 3 * t.spacing
  else
    statusW = inner - rightW - t.space.lg
  end
  status(ui, tools, math.max(0, statusW))
  ui:alignRight(rightW)
  action = drawItems(ui, right, clock, tools) or action
  ui:endWindow()
  if tools.help then
    help(ui, rect, keys)
  end
  return action
end

return M
