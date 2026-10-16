rockspec_format = "3.0"
package = "loupe"
version = "1.2.0-1"
source = {
  url = "git+https://github.com/ChaosDeSelva/loupe.git",
  tag = "v1.2.0",
}
description = {
  summary = "A drop-in live inspector and editor for LÖVE 11.5 games.",
  detailed = [[
Copy the loupe/ folder next to main.lua, watch your game's tables and call loupe.attach().
Press F1 to pause and step time, browse and edit tables live, pick and drag objects in the
world (through cameras and letterboxing), undo/redo, save tweaks to loupe_overrides.lua and
hot-reload changed modules. Includes a standalone immediate-mode UI toolkit (loupe.ui).
Zero dependencies; needs LÖVE 11.5 at runtime.
]],
  license = "MIT",
  labels = { "love2d", "gamedev", "inspector", "debugging", "ui" },
}
dependencies = {
  "lua >= 5.1",
}
build = {
  type = "builtin",
  modules = {
    ["loupe"] = "loupe/init.lua",
    ["loupe.sprites"] = "loupe/sprites.lua",
    ["loupe.collision"] = "loupe/collision.lua",
    ["loupe.window"] = "loupe/window.lua",
    ["loupe.bridge"] = "loupe/bridge.lua",
    ["loupe.core.remote"] = "loupe/core/remote.lua",
    ["loupe.storage"] = "loupe/storage.lua",
    ["loupe.reload"] = "loupe/reload.lua",
    ["loupe.core.clock"] = "loupe/core/clock.lua",
    ["loupe.core.edits"] = "loupe/core/edits.lua",
    ["loupe.core.geometry"] = "loupe/core/geometry.lua",
    ["loupe.core.history"] = "loupe/core/history.lua",
    ["loupe.core.hook"] = "loupe/core/hook.lua",
    ["loupe.core.hotswap"] = "loupe/core/hotswap.lua",
    ["loupe.core.overrides"] = "loupe/core/overrides.lua",
    ["loupe.core.picker"] = "loupe/core/picker.lua",
    ["loupe.core.reflect"] = "loupe/core/reflect.lua",
    ["loupe.core.registry"] = "loupe/core/registry.lua",
    ["loupe.core.serialize"] = "loupe/core/serialize.lua",
    ["loupe.panels.badge"] = "loupe/panels/badge.lua",
    ["loupe.panels.inspector"] = "loupe/panels/inspector.lua",
    ["loupe.panels.layout"] = "loupe/panels/layout.lua",
    ["loupe.panels.objects"] = "loupe/panels/objects.lua",
    ["loupe.panels.toolbar"] = "loupe/panels/toolbar.lua",
    ["loupe.ui"] = "loupe/ui/init.lua",
    ["loupe.ui.context"] = "loupe/ui/context.lua",
    ["loupe.ui.escape"] = "loupe/ui/escape.lua",
    ["loupe.ui.input"] = "loupe/ui/input.lua",
    ["loupe.ui.layout"] = "loupe/ui/layout.lua",
    ["loupe.ui.render_love"] = "loupe/ui/render_love.lua",
    ["loupe.ui.theme"] = "loupe/ui/theme.lua",
    ["loupe.ui.utf8"] = "loupe/ui/utf8.lua",
    ["loupe.ui.widgets"] = "loupe/ui/widgets.lua",
  },
}
