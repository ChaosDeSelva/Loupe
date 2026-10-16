-- The Inspector section: live editors for every field of the selected table.
-- Edits go through edit(target, key, value, keys), where keys lead from the
-- selection's root to the field (default: plain assignment).
local reflect = require("loupe.core.reflect")

local M = {}
M.__index = M

M.MAX_FIELDS = 200

local CHANNELS = { "red", "green", "blue", "alpha" }

function M.new()
  -- expanded: which color fields show their channels, by UI id.
  return setmetatable({ expanded = {} }, M)
end

local function assign(target, key, value)
  target[key] = value
end

function M:color(ui, f, keys, edit)
  -- The id uses the key so it survives the value changing.
  local id = ui:id(f.label .. "#rgba")
  if ui:colorSwatch(f.label .. "##" .. f.label, f.value) then
    self.expanded[id] = not self.expanded[id]
  end
  if self.expanded[id] then
    local indent = ui.theme.indent
    ui:pushId(f.label)
    ui.layout:indent(indent)
    for i = 1, #f.value do
      local v, changed = ui:dragNumber(CHANNELS[i], f.value[i], {
        min = 0,
        max = 1,
        speed = 0.005,
        integer = false, -- 1 and 0 are channel values, not counts
      })
      if changed then
        edit(f.value, i, v, reflect.childKeys(reflect.childKeys(keys, f.key), i))
      end
    end
    ui.layout:unindent(indent)
    ui:popId()
  end
end

function M:fields(ui, t, ancestors, keys, edit)
  local fields = reflect.fields(t)
  local colors = ui.theme.colors
  for i = 1, math.min(#fields, M.MAX_FIELDS) do
    local f = fields[i]
    local label = f.label .. "##" .. f.label
    local v, changed
    if f.kind == "number" then
      v, changed = ui:dragNumber(label, f.value)
    elseif f.kind == "boolean" then
      v, changed = ui:checkbox(label, f.value)
    elseif f.kind == "string" then
      v, changed = ui:textField(label, f.value)
    elseif f.kind == "color" then
      self:color(ui, f, keys, edit)
    elseif f.kind == "table" then
      if ancestors[f.value] then
        ui:valueRow(f.label, "(cycle)")
      elseif
        ui:treeNode(label, { leaf = next(f.value) == nil, count = reflect.summary(f.value) })
      then
        ancestors[f.value] = true
        self:fields(ui, f.value, ancestors, reflect.childKeys(keys, f.key), edit)
        ancestors[f.value] = nil
        ui:treePop()
      end
    else
      ui:valueRow(f.label, reflect.summary(f.value))
    end
    if changed then
      edit(t, f.key, v, reflect.childKeys(keys, f.key))
    end
  end
  if #fields > M.MAX_FIELDS then
    ui:label(("... %d more"):format(#fields - M.MAX_FIELDS), colors.textFaint)
  end
end

-- selection: { value, path, root?, keys?, stale? } or nil. stale: the value is
-- no longer reachable from its root; it's still shown, with a note.
-- rect: where the section goes (panels.layout).
function M:build(ui, selection, rect, edit)
  local c = ui.theme.colors
  local count
  if selection then
    local n = #reflect.fields(selection.value)
    count = n == 1 and "1 field" or (n .. " fields")
  end
  ui:beginWindow("loupe.inspector", "Inspector", {
    x = rect.x,
    y = rect.y,
    w = rect.w,
    h = rect.h,
    docked = true,
    headerRight = count,
    edges = { right = true, top = true },
  })
  if not selection then
    ui:label("Select an object above,", c.textMuted)
    ui:label("or click one in the game.", c.textMuted)
  else
    ui:pathLabel(selection.path, c.accent, "strong")
    if selection.stale then
      ui:label("(no longer in the game)", c.warning, "small")
    end
    ui:separator()
    local ancestors = { [selection.value] = true }
    self:fields(ui, selection.value, ancestors, selection.keys or {}, edit or assign)
  end
  ui:endWindow()
end

return M
