-- SPDX-License-Identifier: AGPL-3.0-only
-- 《永昌守望》LÖVE 11.5 入口。同一份源码也能在 Dora SSR 1.10 的 LoveNode 里运行（见 init.lua）。
local love = require("love")
local App = require("src.app")

local autotest = nil

function love.load(args)
  args = args or {}
  for _, a in ipairs(args) do
    if a == "--autotest" then autotest = require("src.autotest") end
  end
  App.load(args)
  if autotest then autotest.start(App, args) end
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
function love.mousepressed(x, y, b) if not autotest then App.mousepressed(x, y, b) end end
function love.mousereleased(x, y, b) if not autotest then App.mousereleased(x, y, b) end end
function love.mousemoved(x, y) if not autotest then App.mousemoved(x, y) end end
function love.keypressed(key) if not autotest then App.keypressed(key) end end

function love.quit()
  if autotest then autotest.onQuit() end
  return false
end
