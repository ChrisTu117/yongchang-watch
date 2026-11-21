-- SPDX-License-Identifier: AGPL-3.0-only
-- 《永昌守望》LÖVE 11.5 入口。同一份源码也能在 Dora SSR 1.10 的 LoveNode 里运行（见 init.lua）。
local love = require("love")
local App = require("src.app")
local Input = require("src.input")

local autotest = nil

function love.load(args)
  args = args or {}
  for _, a in ipairs(args) do
    if a == "--autotest" then autotest = require("src.autotest") end
  end
  App.load(args)
  Input.init(App)
  if autotest then autotest.start(App, args, Input) end
end

function love.update(dt)
  if autotest then
    autotest.update(dt)
  else
    App.update(dt)
  end
end

function love.draw()
  App.draw()
  if autotest then autotest.afterDraw() end
end

function love.resize(w, h) App.resize(w, h) end
-- 输入统一经过 src/input.lua（桌面 LÖVE 走鼠标回调，Dora 的 LoveNode 把点击作为触摸回调送来）
function love.mousepressed(x, y, b, istouch) if not autotest then Input.mousepressed(x, y, b, istouch) end end
function love.mousereleased(x, y, b, istouch) if not autotest then Input.mousereleased(x, y, b, istouch) end end
function love.mousemoved(x, y) if not autotest then Input.mousemoved(x, y) end end
function love.touchpressed(id, x, y) if not autotest then Input.touchpressed(id, x, y) end end
function love.touchmoved(id, x, y) if not autotest then Input.touchmoved(id, x, y) end end
function love.touchreleased(id, x, y) if not autotest then Input.touchreleased(id, x, y) end end
function love.keypressed(key) if not autotest then Input.keypressed(key) end end

function love.quit()
  if autotest then autotest.onQuit() end
  return false
end
