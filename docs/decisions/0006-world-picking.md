# 0006: World picking captures clicks and prefers the smallest box

- Status: accepted
- Date: 2026-10-09

## Context
Selecting objects by clicking them in the game needs two things: deciding whether a click is
for loupe or the game, and deciding which object was meant when boxes overlap. Games commonly
keep large positioned tables (a camera `{x, y, w, h}`, level bounds) that contain everything.

## Decision
- A toolbar **Pick** switch, on by default. While it's on and the overlay is open, every click
  goes to loupe: clicks on windows go to the UI, clicks in the world select and drag. Turn it
  off (or `attach({ pick = false })`) for games that need the mouse while inspecting.
- Among boxes under the pointer, the **smallest** wins. `attach({ pickable = fn })` can exclude
  objects such as the camera.
- Boxes come from a fallback chain (user `bounds` hook, then `w/h`, `width/height`, radius,
  `def.*`, then a point marker), mapped through the game's `toWorld`/`toScreen`.

## Consequences
- Works in typical games with zero configuration (asteroids needs none).
- Overlapping small objects of equal size resolve to the first found; there's no "click again
  to cycle" yet.
- The `bounds` hook sees every table under the watched roots and must return nil for ones it
  doesn't recognize.
