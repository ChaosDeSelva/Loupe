# 0008: Docked layout, themes with roles, and bundled fonts

- Status: accepted
- Date: 2026-10-09

## Context
Up to 1.0 the overlay was three floating windows at fixed pixel positions (a 340px toolbar at
the top right, Objects and Inspector stacked 280px wide on the left). They ignored the window
size: a resize or fullscreen left them small in a corner, or partly off screen. The theme was
one shared module table, and `panels/badge.lua` read it directly, so overriding colors meant
mutating loupe's own module. Text used LÖVE's 12px default font. Specs clicked fixed pixel
coordinates, so any restyle broke dozens of behavior specs that had nothing to do with looks.

The maintainer asked for a modern, full-screen look: docked edges like Godot or Unity, a clean
dark style (Linear/Figma), crisp text on HiDPI screens, and a theme games can override.

## Decision
- **Docked layout, recomputed every frame.** `panels/layout.lua` (pure) turns the screen size,
  the scaled theme and the splitter state into rects: a full-width top bar, a full-height
  left sidebar split into Objects over Inspector, and the free area left to the game. The game
  still draws full size underneath; only the free area is used for world picking.
- **Docked windows.** `ctx:beginWindow(id, title, { docked = true, ... })` applies the rect
  every frame, never drags and is never brought to front. Floating windows still exist (the
  gallery uses them) and are now clamped so their title bar stays on screen. `popover = true`
  is a docked raised card (the "?" key reference).
- **Splitters.** `ctx:splitter(id, x, y, w, h, axis)` is a drag handle outside any window that
  takes the mouse ahead of the windows it divides. The sidebar width is stored in unscaled
  pixels and the Objects share as a ratio, so both survive resizes and UI scale changes; the
  layout clamps them (minimum widths, room for the game) without forgetting the user's choice.
- **Theme with roles.** `loupe.ui.theme` holds spacing, radii, color roles (surface, border,
  text, textMuted, accent, selection, focus, warning, ...) and font roles (body, strong, small,
  title, mono). `theme.build(overrides, scale)` returns an independent, scaled copy;
  `attach({ theme = ... })` merges into a copy, never into the module. Everything that draws
  (panels, badge, picker highlight) takes the active theme as an argument.
- **Draw commands keep their positional shape** and gain named optional fields
  (`radius`, `width`, `font`) plus `line`, `circle` and `poly` kinds, so existing renderers
  that ignore the new fields still work.
- **Fonts.** Subsets of Inter (Regular, SemiBold) and JetBrains Mono (numbers) ship in
  `loupe/fonts/` (SIL OFL 1.1, ~163 KB total). They are assets, not code dependencies. The
  renderer loads them through `love.filesystem` relative to loupe's module path, or through
  `io` + `love.filesystem.newFileData` when loupe is required via `package.path` from outside
  the game folder. Any failure falls back to LÖVE's default font at the role's size, so
  deleting the folder is safe.
- **Scale.** LÖVE 11 units are already DPI-independent (a Retina window reports points and
  fonts are rasterized at `getDPIScale()`), so multiplying the layout by the DPI scale would
  double everything. Instead the renderer re-rasterizes fonts when `getDPIScale()` changes, and
  the layout scale is `attach({ uiScale = n })` or derived from the window height (1 up to
  ~1260 units tall, then in 0.25 steps, 2 at 2160) for large pixel-unit windows.
- **Specs find widgets by id.** The context records each widget's last-frame rect
  (`ctx:rectOf(id)`); `spec/support/ui_driver.lua` resolves ids or id suffixes to centers.
  Attach specs reach the context through the internal `loupe._debugUi()`.

## Consequences
- The overlay uses the whole window at any size; the game keeps its full-size rendering but
  part of it is covered while the overlay is open (F1 hides it).
- Restyling no longer breaks behavior specs; geometry assertions derive from the theme.
- loupe now ships binary files. The fonts are optional at runtime but add ~163 KB to the folder.
- Games that copied the old theme table must rename colors (`windowBg` -> `surface`,
  `dim` -> `textMuted`, `widget*` -> `control*`/`field*`, `selected` -> `selection`).
- `badge.build` and `picker.highlight` changed signatures (internal modules).
