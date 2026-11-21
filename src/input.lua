-- SPDX-License-Identifier: AGPL-3.0-only
-- 输入转接：把 LÖVE 的鼠标回调和触摸回调统一成“指针”操作交给 App。
-- 为什么需要：桌面 LÖVE 11.5 的鼠标点击走 love.mousepressed；而 Dora SSR 1.10.2 的 LoveNode 把鼠标点击
-- 作为 love.touchpressed 送来（2026-11-21 在 Dora 1.10.2.6 Linux 版实测），鼠标移动仍走 love.mousemoved。
-- 触摸屏上的 LÖVE 会同时发触摸回调和 istouch=true 的鼠标回调。这里两种都接，同一次按下/抬起只处理一次。
local love = require("love")

local Input = {}
local App
local active = nil                     -- 正在按着的那个触摸点
local press = { t = -1, x = 0, y = 0 }
local release = { t = -1, x = 0, y = 0 }

local function now()
  return (love.timer and love.timer.getTime) and love.timer.getTime() or os.clock()
end

-- 同一位置 50 毫秒内的第二次按下（或抬起）视为同一次操作
local function duplicate(rec, x, y)
  local t = now()
  local dup = (t - rec.t) < 0.05 and math.abs(x - rec.x) < 4 and math.abs(y - rec.y) < 4
  rec.t, rec.x, rec.y = t, x, y
  return dup
end

function Input.init(app) App = app end

function Input.mousepressed(x, y, b, istouch)
  if istouch then return end           -- 触摸由 touchpressed 处理
  if duplicate(press, x, y) then return end
  App.mousepressed(x, y, b)
end

function Input.mousereleased(x, y, b, istouch)
  if istouch then return end
  if duplicate(release, x, y) then return end
  App.mousereleased(x, y, b)
end

function Input.mousemoved(x, y) App.mousemoved(x, y) end

function Input.touchpressed(id, x, y)
  if active ~= nil then return end     -- 只认第一根手指
  active = id
  App.mousemoved(x, y)
  if duplicate(press, x, y) then return end
  App.mousepressed(x, y, 1)
end

function Input.touchmoved(id, x, y)
  if id == active then App.mousemoved(x, y) end
end

function Input.touchreleased(id, x, y)
  if id ~= active then return end
  active = nil
  App.mousemoved(x, y)
  if duplicate(release, x, y) then return end
  App.mousereleased(x, y, 1)
end

function Input.keypressed(key) App.keypressed(key) end

return Input
