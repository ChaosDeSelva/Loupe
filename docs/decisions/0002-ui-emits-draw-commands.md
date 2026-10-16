# 0002: The UI emits draw commands; one file renders them

- Status: accepted
- Date: 2026-10-09

## Context
UI code that calls `love.graphics` directly can only be tested with a real window, which makes
coverage targets unrealistic and pushes bugs to manual testing.

## Decision
Widgets and layout append plain-table commands (`{ "rect", x, y, w, h, color }`) to a list each
frame. `loupe/ui/render_love.lua` is the only file that replays them through `love.graphics`.
`loupe/core/` never references `love` at all, and CI enforces that with a grep.

## Consequences
- Layout, widget state and input capture are unit-testable in plain Lua by asserting on commands.
- The renderer stays tiny and is covered by the LÖVE smoke job instead of unit tests.
- The command list is one more indirection to keep in mind when debugging draw order.
