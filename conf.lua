-- SPDX-License-Identifier: AGPL-3.0-only
local love = require("love")

function love.conf(t)
  t.identity = "yongchang-watch"
  t.version = "11.5"
  t.window.title = "永昌守望"
  t.window.width = 1280
  t.window.height = 720
  t.window.minwidth = 640
  t.window.minheight = 360
  t.window.resizable = true
  t.window.vsync = 1
  t.modules.physics = false
  t.modules.joystick = false
  t.modules.video = false
end
