function love.conf(t)
  t.identity = "loupe-asteroids"
  t.version = "11.5"
  t.window.title = "Loupe example: asteroids"
  t.window.width = 960
  t.window.height = 640
  t.window.minwidth = 480
  t.window.minheight = 320
  t.window.resizable = true -- the playfield follows the window
  t.window.highdpi = true -- crisp lines on Retina; sizes stay in points
  t.window.msaa = 4 -- smooths the filled rock and hull edges
  t.modules.physics = false
end
