-- SPDX-License-Identifier: AGPL-3.0-only
-- 录制演示视频用的窗口设置：沿用游戏的 conf.lua（已改名为 game_conf.lua），改成 1920x1080、不等垂直同步。
local love = require("love")
require("game_conf")
local gameConf = love.conf
function love.conf(t)
  gameConf(t)
  t.identity = "yongchang-watch-demo"
  t.window.width = 1920
  t.window.height = 1080
  t.window.resizable = false
  t.window.vsync = 0
end
