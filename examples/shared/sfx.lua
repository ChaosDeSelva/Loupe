-- Sound effects synthesized at load time, so the examples ship no audio files.
-- Each preset returns a duration and a sample generator; generators are called
-- once per sample, in order, so they can keep state (oscillator phase, filters).
local M = {}

-- Watched by the examples, so volume and mute show up in loupe's Inspector.
M.settings = { volume = 0.45, muted = false }

local RATE = 22050
local VOICES = 4 -- copies per sound, so rapid repeats overlap instead of cutting off

local pools = {}
local random = love.math.random

-- An oscillator that integrates frequency into phase, so sweeps stay smooth.
local function osc()
  local phase = 0
  return function(freq)
    phase = (phase + freq / RATE) % 1
    return phase
  end
end

local function square(phase)
  return phase < 0.5 and 1 or -1
end

local function sine(phase)
  return math.sin(phase * math.pi * 2)
end

-- Low-passed noise: smaller k keeps only the rumble.
local function rumble()
  local y = 0
  return function(k)
    y = y + (random() * 2 - 1 - y) * k
    return y
  end
end

local presets = {}

function presets.laser()
  local o = osc()
  return 0.16,
    function(t, p)
      return square(o(1600 * math.exp(-t * 18) + 220)) * 0.22 * (1 - p) ^ 2
    end
end

function presets.boom()
  local n = rumble()
  return 0.7, function(_, p)
    return n(0.14 * (1 - p) + 0.01) * 2.6 * (1 - p) ^ 2
  end
end

function presets.bigBoom()
  local n, o = rumble(), osc()
  return 1.5,
    function(t, p)
      local thump = sine(o(90 * math.exp(-t * 3) + 30)) * 0.5 * math.exp(-t * 4)
      return n(0.08 * (1 - p) + 0.008) * 3.2 * (1 - p) ^ 1.6 + thump
    end
end

function presets.coin()
  local o = osc()
  return 0.28, function(t, p)
    return square(o(t < 0.07 and 988 or 1319)) * 0.16 * (1 - p)
  end
end

function presets.jump()
  local o = osc()
  return 0.17, function(_, p)
    return square(o(260 + 520 * p)) * 0.13 * (1 - p)
  end
end

function presets.land()
  local n = rumble()
  return 0.09, function(_, p)
    return n(0.2) * 1.6 * (1 - p) ^ 2
  end
end

function presets.stomp()
  local o, n = osc(), rumble()
  return 0.22,
    function(_, p)
      return (sine(o(240 - 170 * p)) * 0.5 + n(0.3) * 0.6) * (1 - p) ^ 2
    end
end

function presets.hurt()
  local o, n = osc(), rumble()
  return 0.5,
    function(t, p)
      local saw = o(420 * math.exp(-t * 3)) * 2 - 1
      return (saw * 0.25 + n(0.1) * 0.8) * (1 - p) ^ 1.5
    end
end

-- A rising major arpeggio, used for "you did it" moments.
local function arpeggio(notes, step, length)
  local o = osc()
  return length,
    function(t, p)
      local note = notes[math.min(#notes, math.floor(t / step) + 1)]
      local vibrato = 1 + 0.006 * math.sin(t * 40)
      return square(o(note * vibrato)) * 0.12 * (1 - p) ^ 0.7
    end
end

function presets.start()
  return arpeggio({ 392, 523, 659, 784 }, 0.06, 0.4)
end

function presets.extraLife()
  return arpeggio({ 784, 988, 1175, 1568 }, 0.05, 0.45)
end

function presets.win()
  return arpeggio({ 523, 659, 784, 1047, 1319, 1568 }, 0.11, 1.4)
end

function presets.pop()
  local n, o = rumble(), osc()
  return 0.35,
    function(t, p)
      return (n(0.5) * 0.7 + sine(o(1800 * math.exp(-t * 9))) * 0.2) * (1 - p) ^ 3
    end
end

local function synth(preset)
  local duration, gen = preset()
  local count = math.floor(duration * RATE)
  local data = love.sound.newSoundData(count, RATE, 16, 1)
  for i = 0, count - 1 do
    local s = gen(i / RATE, i / count)
    data:setSample(i, math.max(-1, math.min(1, s)))
  end
  local source = love.audio.newSource(data) -- SoundData always makes a static source
  local pool = { next = 1, source }
  for v = 2, VOICES do
    pool[v] = source:clone()
  end
  return pool
end

-- Builds the named presets. Audio is a nicety, so a machine without a sound
-- device keeps the game running; the reason is printed rather than hidden.
function M.load(names)
  if not (love.audio and love.sound) then
    return
  end
  local ok, err = pcall(function()
    for _, name in ipairs(names) do
      pools[name] = synth(assert(presets[name], "unknown sound " .. tostring(name)))
    end
  end)
  if not ok then
    pools = {}
    print("sfx: sound disabled: " .. tostring(err))
  end
end

-- pitch defaults to 1; jitter adds up to that much random pitch variation.
function M.play(name, pitch, jitter)
  local pool = pools[name]
  local volume = M.settings.volume
  if not pool or M.settings.muted or volume <= 0 then
    return
  end
  local source = pool[pool.next]
  pool.next = pool.next % #pool + 1
  source:stop()
  source:setVolume(math.min(1, volume))
  source:setPitch(math.max(0.05, (pitch or 1) + (random() - 0.5) * 2 * (jitter or 0)))
  source:play()
end

function M.toggleMute()
  M.settings.muted = not M.settings.muted
end

return M
