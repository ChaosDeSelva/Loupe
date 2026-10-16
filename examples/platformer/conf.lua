function love.conf(t)
  t.identity = "loupe-platformer"
  t.version = "11.5"
  t.window.title = "Loupe example: platformer"
  t.window.width = 960
  t.window.height = 640
  t.window.minwidth = 320
  t.window.minheight = 180
  t.window.resizable = true -- the view letterboxes into any size
  t.window.highdpi = true -- crisp text on Retina; sizes stay in points
  t.window.msaa = 4
  t.modules.physics = false
end
