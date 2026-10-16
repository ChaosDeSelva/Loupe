-- The Objects section: a tree of watched roots and the tables inside them.
-- The chevron expands a node; clicking its label picks it for the inspector.
-- Tables with no child tables are leaves: no chevron, and the whole row picks.
-- Each row shows how many fields its table has, right-aligned.
local reflect = require("loupe.core.reflect")

local M = {}

M.MAX_CHILDREN = 200

-- Whether t holds any table the tree would list (colors are shown as values).
local function hasChildTables(t)
  for _, v in pairs(t) do
    if reflect.kind(v) == "table" then
      return true
    end
  end
  return false
end

local function fieldCount(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return tostring(n)
end

local function node(ui, label, idKey, value, path, keys, ctx)
  local open, picked = ui:treeNode(label .. "##" .. idKey, {
    selectable = true,
    selected = ctx.selection ~= nil and ctx.selection.value == value,
    open = ctx.depth == 0,
    leaf = not hasChildTables(value),
    count = fieldCount(value),
  })
  if picked then
    ctx.picked = { value = value, path = path, root = ctx.rootName, keys = keys }
  end
  if not open then
    return
  end

  local children = {}
  for _, f in ipairs(reflect.fields(value)) do
    if f.kind == "table" then
      children[#children + 1] = f
    end
  end

  local faint = ui.theme.colors.textFaint
  ctx.ancestors[value] = true
  ctx.depth = ctx.depth + 1
  for i = 1, math.min(#children, M.MAX_CHILDREN) do
    local f = children[i]
    if ctx.ancestors[f.value] then
      ui:label(f.label .. "  (cycle)", faint)
    else
      local childPath = reflect.childPath(path, f.key)
      node(ui, f.label, f.label, f.value, childPath, reflect.childKeys(keys, f.key), ctx)
    end
  end
  if #children > M.MAX_CHILDREN then
    ui:label(("... %d more"):format(#children - M.MAX_CHILDREN), faint)
  end
  ctx.depth = ctx.depth - 1
  ctx.ancestors[value] = nil
  ui:treePop()
end

-- roots: registry:roots(). selection: { value, path } or nil.
-- rect: where the section goes (panels.layout); a plain { x, y, w, h } is
-- shown docked. Returns the newly picked { value, path, root, keys }, or nil.
function M.build(ui, roots, selection, rect)
  local c = ui.theme.colors
  ui:beginWindow("loupe.objects", "Objects", {
    x = rect.x,
    y = rect.y,
    w = rect.w,
    h = rect.h,
    docked = true,
    headerRight = #roots > 0 and tostring(#roots) or nil,
    edges = { right = true },
    spacing = ui.theme.space.xs,
  })
  if #roots == 0 then
    ui:label("Nothing watched yet.", c.textMuted)
    ui:label('loupe.watch(tbl, "name")', c.textFaint, "mono")
  end

  local ctx = { selection = selection, ancestors = {}, depth = 0 }
  for _, root in ipairs(roots) do
    if root.error then
      ui:label(root.name .. ": " .. root.error, c.warning)
    elseif type(root.value) ~= "table" then
      ui:label(root.name .. " = " .. reflect.summary(root.value), c.textMuted)
    else
      ctx.rootName = root.name
      node(ui, root.name, root.name, root.value, root.name, {}, ctx)
    end
  end
  ui:endWindow()
  return ctx.picked
end

return M
