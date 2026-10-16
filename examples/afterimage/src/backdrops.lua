-- Image loading is isolated from the simulation. Invalid imports leave the active sky intact.
local M = { reducedMotion = false, name = "Deep space", error = nil }
local images, current, previous, fade = {}, nil, nil, 1
local clock, sector = 0, nil
local extensions = { png = true, jpg = true, jpeg = true }
local function loadImage(path)
  local ok, image = pcall(love.graphics.newImage, path)
  if not ok then
    return nil
  end
  if image:getWidth() > 4096 or image:getHeight() > 4096 then
    image:release()
    return nil
  end
  image:setFilter("linear", "linear")
  return { image = image, path = path, name = path:match("([^/]+)%.[^.]+$") or path }
end
local function files(directory)
  local result = {}
  if not love.filesystem.getInfo(directory, "directory") then
    return result
  end
  for _, file in ipairs(love.filesystem.getDirectoryItems(directory)) do
    if extensions[(file:match("%.([^%.]+)$") or ""):lower()] then
      result[#result + 1] = directory .. "/" .. file
    end
  end
  table.sort(result)
  return result
end
local function activate(entry)
  previous, current, fade = current, entry, 0
  M.name = entry.name:gsub("%-", " "):upper()
end
function M.load()
  -- Bound memory even when users add a large asset collection.
  images = {}
  for _, directory in ipairs({ "assets/backgrounds", "imported-backgrounds" }) do
    for _, path in ipairs(files(directory)) do
      if #images < 8 then
        local entry = loadImage(path)
        if entry then
          images[#images + 1] = entry
        end
      end
    end
  end
  if #images > 0 then
    activate(images[love.math.random(#images)])
  end
end
function M.next()
  if #images == 0 then
    return
  end
  local choices = {}
  for _, entry in ipairs(images) do
    if entry ~= current then
      choices[#choices + 1] = entry
    end
  end
  if #choices > 0 then
    activate(choices[love.math.random(#choices)])
  end
end
function M.update(dt, nextSector)
  clock = clock + dt
  fade = math.min(1, fade + dt / 1.8)
  if sector and sector ~= nextSector then
    M.next()
  end
  sector = nextSector
  if fade == 1 then
    previous = nil
  end
end
local function drawImage(entry, alpha, field, player)
  if not entry then
    return
  end
  local img = entry.image
  local movement = M.reducedMotion and 0 or 1
  local scale = math.max(field.w / img:getWidth(), field.h / img:getHeight()) * 1.12
  local driftX = (math.sin(clock * 0.035) * 12 - (player.x - field.x - field.w / 2) * 0.018)
    * movement
  local driftY = (math.cos(clock * 0.028) * 10 - (player.y - field.y - field.h / 2) * 0.014)
    * movement
  love.graphics.setColor(0.84, 0.89, 1, alpha)
  love.graphics.draw(
    img,
    field.x + field.w / 2 + driftX,
    field.y + field.h / 2 + driftY,
    0,
    scale,
    scale,
    img:getWidth() / 2,
    img:getHeight() / 2
  )
end
function M.draw(field, player)
  local lg = love.graphics
  lg.setColor(0.008, 0.015, 0.03)
  lg.rectangle("fill", field.x, field.y, field.w, field.h)
  drawImage(previous, 1, field, player)
  drawImage(current, previous and fade or 1, field, player)
  -- A constant scrim keeps enemy fire readable over any imported image.
  lg.setColor(0.008, 0.018, 0.035, 0.28)
  lg.rectangle("fill", field.x, field.y, field.w, field.h)
  for i = 1, 90 do
    local depth = 1 + i % 3
    local offset = M.reducedMotion and 0 or clock * (5 + depth * 7)
    local x = field.x + (i * 179.32) % field.w
    local y = field.y + (i * 93.71 + offset) % field.h
    local twinkle = M.reducedMotion and 1 or (0.75 + 0.25 * math.sin(clock * 0.8 + i))
    lg.setColor(0.65, 0.85, 1, (0.12 + depth * 0.07) * twinkle)
    lg.circle("fill", x, y, depth == 3 and 1.2 or 0.65)
  end
end
function M.import(file)
  M.error = nil
  local name = file:getFilename():match("[^/\\]+$") or "image"
  if not extensions[(name:match("%.([^%.]+)$") or ""):lower()] then
    M.error = "Use a PNG or JPEG image."
    return false
  end
  if file:getSize() > 8 * 1024 * 1024 then
    M.error = "Image must be under 8 MB."
    return false
  end
  local opened = file:open("r")
  if not opened then
    M.error = "Cannot read this image."
    return false
  end
  local bytes = file:read()
  file:close()
  if not bytes then
    M.error = "Cannot read this image."
    return false
  end
  local ok, data = pcall(love.image.newImageData, love.filesystem.newFileData(bytes, name))
  if not ok then
    M.error = "This image could not be decoded."
    return false
  end
  if data:getWidth() > 4096 or data:getHeight() > 4096 then
    data:release()
    M.error = "Maximum image dimensions: 4096 × 4096."
    return false
  end
  local safeName = name:gsub("[^%w%._%-]", "_")
  local path = "imported-backgrounds/" .. tostring(os.time()) .. "-" .. safeName
  love.filesystem.createDirectory("imported-backgrounds")
  local saved = love.filesystem.write(path, bytes)
  data:release()
  if not saved then
    M.error = "Could not save the imported image."
    return false
  end
  local entry = loadImage(path)
  if not entry then
    M.error = "Could not load the saved image."
    return false
  end
  -- Evict old imports, preserving images currently being crossfaded.
  if #images >= 8 then
    for i, item in ipairs(images) do
      if item ~= current and item ~= previous then
        item.image:release()
        table.remove(images, i)
        break
      end
    end
  end
  images[#images + 1] = entry
  activate(entry)
  return true
end
return M
