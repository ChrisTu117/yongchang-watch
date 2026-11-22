-- SPDX-License-Identifier: AGPL-3.0-only
-- 录制演示视频用的入口（tools/record_demo.sh 把游戏复制到临时目录，原 main.lua 改名为 game_main.lua）。
-- 先载入游戏本身，再把更新和输入交给 demo.lua：游戏按固定步长推进，真实鼠标键盘不起作用。
local love = require("love")
require("game_main")
local Demo = require("demo")

local gameLoad, gameDraw = love.load, love.draw
function love.load()
  gameLoad({})
  Demo.start()
end
function love.update() Demo.update() end
function love.draw()
  gameDraw()
  Demo.afterDraw()
end
local function ignore() end
love.mousepressed, love.mousereleased, love.mousemoved = ignore, ignore, ignore
love.touchpressed, love.touchmoved, love.touchreleased = ignore, ignore, ignore
love.keypressed, love.resize = ignore, ignore
love.quit = function() return false end
