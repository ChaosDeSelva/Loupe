-- A vertical stack with optional side-by-side items (sameLine), right-aligned
-- items (alignRight) and indentation.
local M = {}
M.__index = M

function M.new(x, y, width, spacing)
  return setmetatable({
    left = x,
    width = width,
    spacing = spacing,
    startY = y,
    y = y, -- top of the next row
    lastRight = x,
    lastY = y,
    joinRow = false,
    rightX = nil, -- set by alignRight: where the next item starts
  }, M)
end

-- Reserves a w x h box (w = nil fills the rest of the row) and returns it.
-- A sameLine item that doesn't fit wraps onto a new row.
function M:place(w, h)
  local x, y
  local rowRight = self.left + self.width
  if self.rightX then
    x, y = self.rightX, self.lastY
    if x < self.lastRight + self.spacing then
      x, y = self.rightX, self.y
    end
    self.rightX, self.joinRow = nil, false
  elseif self.joinRow then
    x, y = self.lastRight + self.spacing, self.lastY
    self.joinRow = false
    if w and x + w > rowRight then
      x, y = self.left, self.y
    end
  else
    x, y = self.left, self.y
  end
  w = w or (rowRight - x)

  self.lastRight, self.lastY = x + w, y
  self.y = math.max(self.y, y + h + self.spacing)
  return x, y, w, h
end

function M:sameLine()
  self.joinRow = true
end

-- The next item, `width` wide, ends at the row's right edge.
function M:alignRight(width)
  self.rightX = self.left + self.width - width
end

function M:indent(amount)
  self.left = self.left + amount
  self.width = self.width - amount
end

function M:unindent(amount)
  self:indent(-amount)
end

function M:height()
  return math.max(0, self.y - self.startY - self.spacing)
end

return M
