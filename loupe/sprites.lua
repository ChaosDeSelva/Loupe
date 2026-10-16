-- Grid atlas playback: graphics objects stay in this module, timing is pure and testable.
local M = {}
function M.frame(age, fps, count, loop)
  assert(fps > 0 and count >= 1, "positive fps and frame count required")
  local frame = math.floor(math.max(0, age) * fps)
  if loop then
    return frame % count + 1
  end
  return frame < count and frame + 1 or nil
end
function M.load(path, columns, rows, fps, loop)
  assert(columns >= 1 and rows >= 1 and columns % 1 == 0 and rows % 1 == 0, "integer grid required")
  local image = love.graphics.newImage(path)
  local width, height = image:getDimensions()
  -- Generated sheets can have fractional cell boundaries; LÖVE quads support these.
  assert(width >= columns and height >= rows, "atlas must have at least one pixel per cell")
  local sheet = {
    image = image,
    width = width / columns,
    height = height / rows,
    fps = fps,
    loop = loop,
    count = columns * rows,
    quads = {},
  }
  image:setFilter("linear", "linear")
  for index = 0, sheet.count - 1 do
    sheet.quads[index + 1] = love.graphics.newQuad(
      index % columns * sheet.width,
      math.floor(index / columns) * sheet.height,
      sheet.width,
      sheet.height,
      width,
      height
    )
  end
  return sheet
end
function M.draw(sheet, age, x, y, width, height, rotation)
  local frame = M.frame(age, sheet.fps, sheet.count, sheet.loop)
  if not frame then
    return false
  end
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(
    sheet.image,
    sheet.quads[frame],
    x,
    y,
    rotation or 0,
    width / sheet.width,
    (height or width) / sheet.height,
    sheet.width / 2,
    sheet.height / 2
  )
  return true
end
return M
