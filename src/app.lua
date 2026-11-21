-- SPDX-License-Identifier: AGPL-3.0-only
-- 场景管理、存档、输入分发。
local love = require("love")
local G = require("src.gfx")
local A = require("src.audio")

local App = { scene = nil, time = 0, save = { unlocked = 1, stars = {} }, args = {} }

local SAVE_FILE = "progress.txt"

function App.loadSave()
  App.save = { unlocked = 1, stars = {} }
  if not love.filesystem.getInfo or not love.filesystem.getInfo(SAVE_FILE) then return end
  local ok, data = pcall(love.filesystem.read, SAVE_FILE)
  if not ok or not data then return end
  for k, v in data:gmatch("(%w+)=(%d+)") do
    local n = tonumber(v)
    if k == "unlocked" then App.save.unlocked = math.max(1, math.min(4, n))
    else
      local i = tonumber(k:match("^stars(%d)$"))
      if i then App.save.stars[i] = math.min(3, n) end
    end
  end
end

function App.writeSave()
  local parts = { "unlocked=" .. string.format("%d", App.save.unlocked) }
  for i = 1, 3 do
    if App.save.stars[i] then parts[#parts + 1] = "stars" .. i .. "=" .. string.format("%d", App.save.stars[i]) end
  end
  pcall(love.filesystem.write, SAVE_FILE, table.concat(parts, "\n") .. "\n")
end

function App.record(level, stars)
  local old = App.save.stars[level] or 0
  if stars > old then App.save.stars[level] = stars end
  if level + 1 > App.save.unlocked then App.save.unlocked = level + 1 end
  App.writeSave()
end

function App.go(name, params)
  local mod = require("src.scenes." .. name)
  local scene = mod.new(App, params or {})
  App.scene = scene
  App.sceneName = name
  print("[永昌守望] scene: " .. name)
  if App.onScene then App.onScene(name, scene) end
end

function App.load(args)
  App.args = args or {}
  if love.graphics.setDefaultFilter then love.graphics.setDefaultFilter("linear", "linear") end
  G.resize(love.graphics.getDimensions())
  App.loadSave()
  A.load()
  App.go("title")
end

function App.update(dt)
  App.time = App.time + dt
  if App.scene and App.scene.update then App.scene:update(dt) end
end

function App.draw()
  love.graphics.clear(0.02, 0.02, 0.04, 1)
  love.graphics.push()
  love.graphics.translate(G.ox, G.oy)
  love.graphics.scale(G.scale, G.scale)
  -- 画面外的黑边不画内容
  love.graphics.setScissor(G.ox, G.oy, math.ceil(G.W * G.scale), math.ceil(G.H * G.scale))
  if App.scene and App.scene.draw then App.scene:draw() end
  love.graphics.setScissor()
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1, 1)
end

function App.resize(w, h) G.resize(w, h) end

function App.mousepressed(x, y, b)
  local lx, ly = G.toLogical(x, y)
  if App.scene and App.scene.mousepressed then App.scene:mousepressed(lx, ly, b) end
end

function App.mousereleased(x, y, b)
  local lx, ly = G.toLogical(x, y)
  if App.scene and App.scene.mousereleased then App.scene:mousereleased(lx, ly, b) end
end

function App.mousemoved(x, y)
  local lx, ly = G.toLogical(x, y)
  App.mx, App.my = lx, ly
  if App.scene and App.scene.mousemoved then App.scene:mousemoved(lx, ly) end
end

function App.keypressed(key)
  if key == "m" then A.toggleMute(); return end
  if App.scene and App.scene.keypressed then App.scene:keypressed(key) end
end

-- 鼠标在逻辑坐标里的位置
function App.mouse()
  if App.mx then return App.mx, App.my end
  local x, y = love.mouse.getPosition()
  return G.toLogical(x, y)
end

function App.quit(code)
  App.quitting = true
  love.event.quit(code or 0)
end

return App
