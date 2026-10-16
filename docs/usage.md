# Playing with Loupe

Start with the [three-line setup](../README.md#quick-start), then use this guide for controls, cameras, and example experiments.

## Cameras and letterboxing

Pass functions that map points between screen and world, and keep big positioned tables (like a
camera) from being clicked. From [`examples/platformer`](../examples/platformer/main.lua), which
letterboxes a 640x360 virtual resolution and follows the player with a camera:

```lua
-- src/view.lua
function M.toScreen(wx, wy)
  return (wx - camera.x) * scale + offsetX, (wy - camera.y) * scale + offsetY
end

function M.toWorld(sx, sy)
  return (sx - offsetX) / scale + camera.x, (sy - offsetY) / scale + camera.y
end

-- main.lua
loupe.watch(function() return game end, "game")
loupe.attach({
  toWorld = view.toWorld,
  toScreen = view.toScreen,
  pickable = function(obj)
    return not (game and obj == game.camera)
  end,
})
```

Objects get a box from `x, y` plus `w/h`, `width/height`, or `r/radius` (also looked up in
`obj.def`). For anything else, pass `bounds = function(obj) ... end` and return `nil` for tables
you don't recognize.

## Keys

| Key | Action | When |
|---|---|---|
| F1 | Show/hide loupe | Always |
| P | Pause / resume | Overlay open |
| `.` | Step one frame | Overlay open |
| `[` / `]` | Slower / faster | Overlay open |
| `1` | Reset speed to x1 | Overlay open |
| Ctrl/Cmd+Z | Undo | Overlay open |
| Ctrl/Cmd+Shift+Z, Ctrl/Cmd+Y | Redo | Overlay open |
| Ctrl/Cmd+S | Save overrides | Overlay open |
| Shift+Left/Right/Home/End | Extend the selection | Typing in a field |
| Ctrl/Cmd+A | Select all | Typing in a field |
| Ctrl/Cmd+C / X / V | Copy / cut / paste | Typing in a field |

F1 and the time keys can be rebound with `attach({ keys = { toggle = "f2", ... } })`. While you're
typing in a loupe field, keys go to the field, except F1 and Ctrl/Cmd+Z, Y and S.

## Examples

Run them from the repo root with LÖVE 11.5. Both games open resizable, HiDPI-aware windows;
F11 or Alt+Enter toggles fullscreen and M mutes. None of these clash with loupe's keys.

| Command | Controls | Demonstrates |
|---|---|---|
| `love examples/asteroids` | Enter start, arrows/WASD fly, Space fire, R restart, Esc quit | Zero-configuration setup: a getter root, shared definition tables (`rockSizes`), module-level tunables (`bullets`, `fx`, `sound`), picking radius-based objects, undo and saved overrides. Glowing vector art, particles, screen shake, a parallax starfield, 3 lives and waves. |
| `love examples/platformer` | Enter start, arrows/WASD move, Space/Up/W jump, R restart, Esc quit | World picking through a smoothed camera and a letterboxed 640x360 view in any window size; excluding the camera with `pickable`; a game that switches scenes. Parallax backdrop, coyote time, jump buffering, squash and stretch, stompable enemies and a level-complete celebration. |
| `love examples/ui_gallery` | Mouse, Esc quit | Every `loupe.ui` widget, wired into LÖVE by hand without the rest of loupe. |

Worth dragging live (F1, then select in Objects or click in the world):

- **asteroids:** `fx.glow` (0 turns the glow off), `fx.shakeStrength`, `fx.stars`,
  `fx.maxParticles`; `game.ship.thrust`, `turnSpeed`, `maxSpeed`; `rockSizes.large.r` (every
  large rock grows); `bullets.speed`, `radius` and `color`; `sound.volume`.
- **platformer:** `game.player.jump`, `gravity`, `fallGravity`, `jumpCut`, `coyoteTime`,
  `jumpBuffer`, `squash`; `game.camera.smoothing` and `lookAhead`; `game.fx.confetti`;
  `game.backdrop.skyTop`; drag `game.spawn` to start somewhere else.

Add `--smoke N` to any example to run N frames unattended and exit. The examples load loupe and
`examples/shared/` from the repo; a copy taken out of the repo needs both.

