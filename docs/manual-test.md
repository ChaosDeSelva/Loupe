# Manual test checklist

Run one LÖVE process at a time. Items are added as milestones land.

## M0
- [ ] `love examples/asteroids` opens a 960x640 window on the title screen; Enter starts.
- [ ] Arrows (or WASD) turn and thrust, space fires, rocks split into smaller rocks, score goes up.
- [ ] The ship blinks for 2.5 seconds after start and after each respawn (invulnerable); after that, touching a rock costs a life. You have 3; losing the last one shows GAME OVER.
- [ ] R restarts, Esc quits.
- [ ] Clearing all rocks starts the next wave, after a short pause and a "WAVE n" banner, with one more rock.
- [ ] `love examples/asteroids --smoke 90` exits by itself with code 0.

## M1
- [ ] `love examples/asteroids` with loupe closed plays exactly like M0, with no overlay.
- [ ] F1 shows the bar in the top right; F1 again hides it. The game never reacts to F1.
- [ ] With the bar open: P pauses (rocks freeze, holding space fires nothing) and P resumes.
- [ ] `.` steps one frame at a time while paused; holding `.` advances slowly.
- [ ] `]` speeds up (x2, x4); `[` slows down (down to x0.1); `1` resets to x1.
- [ ] Hide the bar while paused or at a different speed: a small badge stays visible.
- [ ] With the bar closed, P / . / [ / ] / 1 do nothing special.
- [ ] Space and the arrow keys still reach the game while the bar is open.

## M2
UI gallery (`love examples/ui_gallery`):
- [ ] Each window drags by its title bar; clicking a window brings it to the front.
- [ ] "Click me" counts clicks; "Reset" zeroes the count. Pressing a button, moving off it, and releasing does not click.
- [ ] Checkbox toggles; "Current values" updates.
- [ ] speed: drag left/right changes it smoothly; a plain click lets you type. Enter commits, Esc cancels, clicking elsewhere commits.
- [ ] lives stays a whole number between 0 and 9 whether dragged or typed.
- [ ] name: click, type (including accented letters), Backspace removes one whole character, Enter commits.
- [ ] tint tree opens; dragging r/g/b/a recolors the circle.
- [ ] The scroll window scrolls with the wheel and stops at both ends; the scrollbar thumb moves.
- [ ] Esc quits only when no field is being edited.

Asteroids:
- [ ] F1 shows the "loupe" window. Pause/Resume, Step, -, +, and the speed button (resets) all work by mouse.
- [ ] Clicking loupe's buttons never fires or steers the ship. Clicks elsewhere still reach the game.
- [ ] The window can be dragged anywhere and stays put when toggled with F1.

## M3
Asteroids (`love examples/asteroids`, then F1):
- [ ] Objects lists `game` (open), `rockSizes`, `bullets`, `fx` and `sound`. `game` shows bullets, rocks, ship.
- [ ] The arrow expands a node; clicking a label selects it (highlighted) and the Inspector shows it.
- [ ] Select `ship`: drag `thrust` up and the ship accelerates faster; set `turnSpeed` to 10 and it spins fast.
- [ ] Click `color` to show red/green/blue/alpha; drag them and the ship recolors.
- [ ] Expand `rockSizes` > `large`, raise `r`: every large rock grows (the def table is shared).
- [ ] `bullets.speed`, `bullets.life`, `bullets.radius` and `bullets.color` change the next shots fired.
- [ ] `game.score`: type 9999 and press Enter; the HUD counts up to it.
- [ ] While typing in a field, P / . / [ / ] / 1 type text and don't touch game time.
- [ ] Press R to restart: Objects shows the new game (the getter follows it).
- [ ] Expand `rocks` while rocks split: open/closed state stays put as the count changes.

## M4
Platformer (`love examples/platformer`, Enter to start, then F1):
- [ ] Hovering a platform, coin, enemy, the flag, the spawn marker (`game.spawn`), or the player draws a thin outline that lines up exactly.
- [ ] Clicking selects it: blue outline, path label (e.g. `game.platforms[5]`), and the Inspector shows it.
- [ ] Dragging moves it smoothly under the pointer; the Inspector's x/y update live.
- [ ] Resize the window (bars change): picking and dragging still line up.
- [ ] Walk right so the camera scrolls: picking still lines up.
- [ ] The camera can't be picked, even when clicking empty sky.
- [ ] Pick: on means the game doesn't see clicks; switch it off in the toolbar and clicks go back to the game.
- [ ] Selecting in the world highlights the same entry in Objects (when its parent is expanded).

Asteroids:
- [ ] With no extra setup, rocks (`r`) and the ship are pickable. Pause (P), then drag rocks around.

## M5
Asteroids (`love examples/asteroids`, F1):
- [ ] Drag a rock (Pick on, paused), then Ctrl+Z (Cmd+Z on macOS): it jumps back in one step, x and y together.
- [ ] Ctrl+Shift+Z or Ctrl+Y redoes. The Undo/Redo buttons do the same.
- [ ] Any edit shows "unsaved changes" in the toolbar.
- [ ] Ctrl+S or Save writes `examples/asteroids/loupe_overrides.lua` (readable, one line per value, path comments). The console prints the path.
- [ ] Quit and relaunch: the toolbar says "loaded N saved overrides" and the values are back.
- [ ] Undo a tweak back to its original value and save: its line disappears from the file.
- [ ] Press R (restart): saved values re-apply to the new game.
- [ ] Break the file (e.g. delete the final `}`): loupe shows "couldn't read ..." and the game still runs.
- [ ] With the overlay closed, Ctrl+Z reaches the game.

## M6: hot reload
Run an example unfused from its folder (`love examples/asteroids`) and open loupe (F1).
- [ ] Edit a function in one of its modules (e.g. how `src/ship.lua` draws the ship) and save. Within about half a second the change shows in the running game, and the toolbar says `reloaded src.ship`.
- [ ] Objects created before the edit pick up the new code.
- [ ] Change a module constant and save: the new value applies. A module value changed at runtime (or in the Inspector) survives a save that doesn't touch that line.
- [ ] Save a syntax error: the game keeps running on the old code, the toolbar shows `reload failed: src.ship: Syntax error ...` in the warning colour, and the console prints it. Fix it and save: `reloaded src.ship`.
- [ ] Add `error("boom")` at the top of a module and save: same behaviour, no crash.
- [ ] With the overlay hidden, save a broken module: the corner badge shows the failure until you open the overlay.
- [ ] Save two modules within half a second: `reloaded 2 modules`.
- [ ] Pause (P), edit and save: the reload still happens.
- [ ] `loupe.attach({ hotReload = false })` turns reloads off; `reloadIgnore = { "^src%.ship$" }` skips that module.
- [ ] Run as a `.love` or fused: no reload happens and nothing errors.
- [ ] Editing `main.lua`, `conf.lua` or anything under `loupe/` never triggers a reload.

## 1.0 polish and integration
- [ ] Objects: a table with no child tables (e.g. `ship`) shows no arrow; clicking anywhere on its row, even where the arrow would be, selects it. Tables with children still show `>` / `v`.
- [ ] Inspector: an empty nested table (`{}`) shows no arrow.
- [ ] Text field: click a string, press Left twice, type `X`: it goes in at the cursor. Home/End jump to the ends; Delete removes the character after the cursor, Backspace the one before. Text with `é` or an emoji moves and deletes one character at a time.
- [ ] Holding Backspace or an arrow key repeats while editing; afterwards the game's own key-repeat setting is unchanged.
- [ ] A string longer than its field: End keeps the end visible while typing; Home shows the start. Clicking inside the field while editing moves the cursor.
- [ ] Number field: click to type, press Home, type `-`, Enter: the value is negated.
- [ ] World pick where objects overlap: the first click selects the smallest, each further click at the same spot the next larger, wrapping around. After cycling to an object, press and drag moves that object. Clicking elsewhere starts over.
- [ ] Long Objects/Inspector lists: scrolling reaches the last row, the scrollbar matches, nothing flickers at the edges.
- [ ] Select a rock, then shoot it: the Inspector shows "(no longer in the game)".
- [ ] Pick something in the world, edit a field in the Inspector, save: the value is in `loupe_overrides.lua` (this was broken before 1.0).
- [ ] After saving, make another edit: "unsaved changes" shows next to Save while the "saved N overrides" message stays visible.

## 1.1 hardening
Written from `docs/ai-log/1.1-hardening.md`. None of this was run in LÖVE before merge; only
specs cover it, so this is the smoke run still owed.
- [ ] `love examples/asteroids --smoke 120` and `love examples/platformer --smoke 120` still exit by themselves with code 0.
- [ ] Callback chaining: in a scratch copy of an example, after `loupe.attach()` add `local old = love.update; love.update = function(dt) old(dt) end` inside `love.load`. The game runs, F1 works, and there's no stack overflow. (With hump available: `Gamestate.registerEvents()` in `love.load` behaves the same.)
- [ ] Error boundary: pass `attach({ bounds = function() error("boom") end })` in a scratch copy, open loupe (F1). The overlay closes, the badge reads "loupe hit an error (see console) - F1 to reopen", the console prints `loupe: ...boom` with a traceback once, and the game keeps playing. F1 reopens (and closes again while the hook still throws).
- [ ] Odd keys: watch a table keyed by a table or function (e.g. `loupe.watch({ [{}] = { v = 1 } }, "odd")`) and edit `v` in the Inspector. The value changes, Ctrl/Cmd+Z undoes it, and the toolbar shows "can't save odd[table: 0x...].v: it's reached through a key that isn't a string or number". Nothing crashes.
- [ ] Ctrl/Cmd+S while typing in an Inspector field saves (console prints the path) and the field stays in edit mode. Ctrl/Cmd+Z and Ctrl/Cmd+Y while typing undo and redo.
- [ ] Undo after restart: in asteroids change `game.ship.thrust`, press R, then Ctrl/Cmd+Z: the undo applies to the new game's ship.
- [ ] Save writes `loupe_overrides.lua` and leaves no `loupe_overrides.lua.tmp` behind. Make the example folder read-only and save: the toolbar shows "save failed: ..." and the old file is intact.
- [ ] Put `while true do end` in `loupe_overrides.lua` and start the game: it starts, and the toolbar shows "couldn't read loupe_overrides.lua: ... took too long to run ...".
- [ ] Hot reload with a custom require path: in a scratch game call `love.filesystem.setRequirePath("src/?.lua;?.lua")` and `require("ship")`; editing `src/ship.lua` shows `reloaded ship`.
- [ ] Windows only: tweak a value to an integer above 2^31 (e.g. 3000000000), save, relaunch: it comes back exactly.

## 1.1 examples
Written from `docs/ai-log/1.1-examples.md`, which lists what wasn't verified on screen.

Both examples:
- [ ] F11 toggles desktop fullscreen and back; Alt+Enter does the same and never also starts or restarts the game. The layout refits at once.
- [ ] The window resizes down to its minimum (asteroids 480x320, platformer 320x180) with everything still visible.
- [ ] On a Retina/HiDPI display, lines and text are sharp, not blurry.
- [ ] M mutes and unmutes. Sounds play (laser, explosions, jump, coin chime rising in pitch). With no audio device, the game still runs and prints why.
- [ ] Open loupe (F1) over the game: the overlay draws normally (the game's blend mode, line join and font don't leak into it).
- [ ] Frame rate stays smooth (asteroids has about 170 polygon draws a frame with glow, the platformer about 300).
- [ ] Look: glow strength, colors, text placement and sizes, parallax and squash amounts look right. The values are first guesses; note any you'd change.

Asteroids:
- [ ] Title screen shows ASTEROIDS, "PRESS ENTER" and the controls line; rocks drift behind it; Space does nothing there.
- [ ] Explosions throw streaks and shards with a shock ring and a score popup; the screen shakes; the ship's death flashes white.
- [ ] Thrusting leaves a particle trail; the starfield shifts with the ship's speed.
- [ ] Objects straddling an edge draw on both sides; a rock half across the edge still hits the ship and bullets on the other side.
- [ ] Losing a ship drops lives by one and respawns at the center with a shield; after 3, GAME OVER, and Enter or R restarts. BEST keeps the session's best score.
- [ ] Reaching 10,000 points shows "1UP" and adds a life.
- [ ] Resize or go fullscreen mid-game: rocks, bullets and the ship fold into the new field.
- [ ] `fx`: set `glow` to 0 (glow off) and back; `stars` to 0 and to 1000; `maxParticles` to 0 (no particles, no errors); `shakeStrength` to 0.
- [ ] While the screen shakes, picking outlines lag by a few pixels (known limitation); pause and they line up.
- [ ] Inspector: edit `bullets.color` and `rockSizes.large.color`; new bullets and large rocks change color.

Platformer:
- [ ] Title screen, then Enter. A quick tap of jump gives a short hop; holding it gives a full jump that reaches every ledge.
- [ ] Jump pressed just before landing still jumps (buffer); jump just after running off a ledge still works (coyote). With `game.player.coyoteTime` at 0 it doesn't.
- [ ] The player squashes on landing and stretches on take-off; `squash` at 0 turns it off.
- [ ] The camera eases after the player and leads in the facing direction, and stays inside the level.
- [ ] The sky, sun, clouds and three ridges scroll at different speeds; the nearest ridge has trees.
- [ ] Coins bob and twinkle; collecting one bursts sparks, shows "+1" and chimes.
- [ ] Landing on an enemy stomps it and bounces; touching one from the side kills the player, who respawns at `game.spawn`. Falling into a pit does the same and counts a fall.
- [ ] Reaching the flag raises it, the timer stops, confetti and fireworks play, and "LEVEL COMPLETE!" shows coins, time and falls. Enter plays again.
- [ ] Text stays sharp in fullscreen; picking and dragging still line up in fullscreen and in a tall narrow window.
- [ ] Drag `game.spawn` in the world, then fall into a pit: the player respawns there.

## 1.1 UI redesign

Asteroids or platformer, F1:
- [ ] The top bar spans the full width and the sidebar the full height below it; the game is still visible to the right.
- [ ] Resize the window, and toggle fullscreen (F11): the bar and sidebar follow, and nothing ends up off screen.
- [ ] Drag the sidebar's right edge and the Objects/Inspector divider: a resize cursor shows, and the sizes persist across window resizes.
- [ ] Pick is the switch in the top bar; clicking it gives clicks back to the game.
- [ ] Edit something: "unsaved changes" shows in the top bar; status messages ("loaded N saved overrides", "reloaded src.ship", "reload failed ...") show there too.
- [ ] **?** opens the key reference; a click outside closes it.
- [ ] Drag a whole-number field: it moves in whole steps. Hold Shift: fine steps.
- [ ] On a Retina screen (the examples set `highdpi = true`), text is crisp.
- [ ] Delete `loupe/fonts`: LÖVE's default font is used and the layout stays intact (restore it after).
- [ ] Very long string values are shortened with an ellipsis instantly, with no hitch.

## 1.1.1
Written from the scripted LÖVE run in `docs/ai-log/1.1.1-ui-finish.md`. UI gallery
(`love examples/ui_gallery`) or an example with loupe open (F1):
- [ ] A string with a newline and a tab (the gallery's `note`, or `note = "first line\nsecond\tline"` in a watched table) shows on one row as `first line\nsecond\tline`, with nothing spilling into the rows below.
- [ ] Edit a string such as "bobby", press End, then Shift+Left three times: "bby" is highlighted. Left or Right collapses the selection; Ctrl/Cmd+A selects everything.
- [ ] Copy text with newlines to the clipboard (e.g. "pasted" and "from clipboard" on two lines), select part of a field and press Ctrl/Cmd+V: the selection is replaced, the field shows the escaped form (`\n`), and after Enter the value holds a real newline. Ctrl/Cmd+C and X copy and cut the selection to the system clipboard.
- [ ] In the Inspector, drag a number field holding 0.2 (its drag speed is 0.05 per pixel) three pixels left: it reads `0.05` and the live value is 0.05, not 0.049999999999999989. Save: the file says `0.05`.
- [ ] With the overlay open, press `p` (pause), then `q`: the game gets only `q`'s text and release, never `p`'s text or release.
- [ ] With the bundled fonts, newlines and tabs show as `\n` and `\t` (the subsets have no "↵"; only Inter has "→"). (Optional: with fonts that have both glyphs, such as re-subset ones with U+21B5 and U+2192, loupe shows the arrows instead.)
