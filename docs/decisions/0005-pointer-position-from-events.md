# 0005: Pointer position comes from events, not per-frame polling

- Status: accepted
- Date: 2026-10-09

## Context
The first version of the overlay read `love.mouse.getPosition()` at the start of every UI frame.
Clicks arrive as events between frames, so polling replaced the position the click actually
happened at with wherever the pointer was a moment later. A real-LÖVE run with scripted clicks
showed none of them landing; the unit tests had hidden it by moving the fake mouse to the click
point.

## Decision
`ui/input` takes the pointer position only from `mousemoved`, `mousepressed` and
`mousereleased` events. The host polls once, at `attach` (or `love.load` for standalone use), to
have a starting position. loupe always receives `mousemoved`, even while hidden.

## Consequences
- Every press is hit-tested at the exact point it happened.
- Code that synthesizes input must send events, not move the mouse. The attach spec now
  clicks with the polled mouse at (0, 0) to guard against regressions.
