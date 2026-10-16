-- Original effects and three original compositions; independent, live-adjustable buses.
local M = { muted = false, musicVolume = 0.85, effectsVolume = 0.85 }
local tracks, sources, active = {}, {}, 1
local tones = {
  shot = { 720, 0.075, 0.55 },
  kill = { 90, 0.22, 0.72 },
  pickup = { 1100, 0.13, 0.58 },
  hurt = { 55, 0.28, 0.8 },
  level = { 1400, 0.25, 0.65 },
  complete = { 660, 0.5, 0.7 },
  buy = { 880, 0.19, 0.7 },
  lost = { 65, 0.6, 0.75 },
}
local function clamp(value)
  return math.max(0, math.min(1, value))
end
function M.load()
  for i, name in ipairs({ "glasslight", "violet-current", "ember-orbit" }) do
    local source = love.audio.newSource("assets/" .. name .. ".ogg", "static")
    source:setLooping(true)
    source:setVolume(0)
    tracks[i] = source
  end
  tracks[1]:setVolume(M.musicVolume * 0.8)
  tracks[1]:play()
  for name, tone in pairs(tones) do
    local rate = 22050
    local data = love.sound.newSoundData(math.floor(rate * tone[2]), rate, 16, 1)
    for i = 0, data:getSampleCount() - 1 do
      local t = i / rate
      local envelope = math.min(1, t / 0.003) * (1 - t / tone[2]) ^ 1.5
      local frequency = tone[1] * (name == "shot" and (1 - t / tone[2] * 0.5) or 1)
      data:setSample(i, math.sin(t * frequency * math.pi * 2) * envelope * tone[3])
    end
    sources[name] = love.audio.newSource(data, "static")
  end
end
function M.play(name)
  if M.muted or not sources[name] then
    return
  end
  local source = sources[name]:clone()
  source:setVolume(M.effectsVolume)
  source:play()
end
function M.setMuted(value)
  M.muted = value
  if value then
    for _, source in ipairs(tracks) do
      source:setVolume(0)
    end
  end
end
function M.setVolume(bus, value)
  if bus == "music" then
    M.musicVolume = clamp(value)
  elseif bus == "effects" then
    M.effectsVolume = clamp(value)
  end
end
function M.update(dt, screen, pattern)
  active = pattern or 1
  for i, source in ipairs(tracks) do
    local target = not M.muted and i == active and M.musicVolume * (screen == "flight" and 1 or 0.8)
      or 0
    local volume = source:getVolume() + (target - source:getVolume()) * math.min(1, dt * 2)
    source:setVolume(volume)
    if i == active and not source:isPlaying() then
      source:play()
    elseif i ~= active and volume < 0.001 then
      source:stop()
    end
  end
end
return M
