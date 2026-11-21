-- SPDX-License-Identifier: AGPL-3.0-only
local love = require("love")
local G = require("src.gfx")
local A = require("src.audio")
local L = require("src.data.levels")

local Title = {}
Title.__index = Title

function Title.new(app)
  local s = setmetatable({ app = app, t = 0, lanterns = {} }, Title)
  A.playMusic("music_title")
  local bx, bw, bh = 380, 200, 40
  s.buttons = {}
  local y = 300
  local function add(id, label)
    s.buttons[#s.buttons + 1] = { id = id, label = label, x = bx, y = y, w = bw, h = bh }
    y = y + 50
  end
  add("start", "从第一夜开始")
  local u = app.save.unlocked
  if u >= 2 and u <= L.count then add("continue", "继续：第" .. ({ "一", "二", "三" })[u] .. "夜") end
  if u > L.count then add("finale", "再看终章") end
  add("help", "操作说明")
  add("quit", "退出游戏")
  for i = 1, 14 do
    s.lanterns[i] = { x = (i * 71) % 960, y = 540 + (i * 37) % 300, v = 8 + (i * 13) % 12, sw = i }
  end
  return s
end

function Title:update(dt)
  self.t = self.t + dt
  for _, l in ipairs(self.lanterns) do
    l.y = l.y - l.v * dt
    if l.y < -20 then l.y = 560 end
  end
end

function Title:button(id)
  for _, b in ipairs(self.buttons) do if b.id == id then return b end end
end

function Title:draw()
  -- 夜空与海
  love.graphics.setColor(0.04, 0.06, 0.13)
  love.graphics.rectangle("fill", 0, 0, 960, 540)
  love.graphics.setColor(0.05, 0.10, 0.20)
  love.graphics.rectangle("fill", 0, 360, 960, 180)
  for i = 0, 14 do
    local y = 372 + i * 12
    love.graphics.setColor(0.12, 0.22, 0.38, 0.5 - i * 0.03)
    love.graphics.setLineWidth(1)
    local ph = self.t * 0.6 + i
    love.graphics.line(0, y + math.sin(ph) * 2, 960, y + math.sin(ph + 2) * 2)
  end
  -- 月亮
  love.graphics.setColor(0.95, 0.9, 0.75, 0.9)
  love.graphics.circle("fill", 780, 90, 34)
  love.graphics.setColor(0.04, 0.06, 0.13)
  love.graphics.circle("fill", 793, 82, 30)
  -- 城墙剪影
  love.graphics.setColor(0.10, 0.09, 0.10)
  love.graphics.rectangle("fill", 80, 300, 800, 70)
  for x = 80, 870, 22 do love.graphics.rectangle("fill", x, 290, 12, 12) end
  for _, tx in ipairs({ 130, 330, 630, 830 }) do
    love.graphics.rectangle("fill", tx - 24, 260, 48, 110)
    love.graphics.polygon("fill", tx - 34, 262, tx, 236, tx + 34, 262)
    love.graphics.setColor(1, 0.75, 0.35, 0.8 + 0.2 * math.sin(self.t * 3 + tx))
    love.graphics.rectangle("fill", tx - 6, 282, 12, 14)
    love.graphics.setColor(0.10, 0.09, 0.10)
  end
  -- 孔明灯
  for _, l in ipairs(self.lanterns) do
    -- 画面外的不画（Dora 的 LoveNode 不按 setScissor 裁剪画面外的内容）
    if l.y > 552 then goto skip end
    local x = l.x + math.sin(self.t + l.sw) * 6
    love.graphics.setColor(1, 0.6, 0.25, 0.25)
    love.graphics.circle("fill", x, l.y, 10)
    love.graphics.setColor(1, 0.72, 0.35, 0.9)
    love.graphics.rectangle("fill", x - 4, l.y - 6, 8, 11, 2, 2)
    ::skip::
  end
  G.text("永昌守望", 480, 92, 76, G.C.gold, "center")
  G.text("守 · 望", 480, 190, 26, G.C.ink, "center")
  G.text("一座古堡，三夜守望，拼出天下太平", 480, 232, 16, G.C.dim, "center")
  local mx, my = self.app.mouse()
  for _, b in ipairs(self.buttons) do G.button(b, G.inRect(mx, my, b)) end
  local stars = self.app.save.stars
  if stars[1] then
    local line = {}
    for i = 1, L.count do line[#line + 1] = "第" .. i .. "夜 " .. string.rep("★", stars[i] or 0) .. string.rep("☆", 3 - (stars[i] or 0)) end
    G.text(table.concat(line, "    "), 480, 512, 13, G.C.dim, "center")
  end
  G.text("2026 开源游戏开发大赛 · 主题「守·望」", 12, 516, 12, G.C.dim, "left")
  G.text("M 静音", 948, 516, 12, G.C.dim, "right")
end

function Title:activate(id)
  A.play("click")
  local app = self.app
  if id == "start" then
    app.go("story", { level = 1 })
  elseif id == "continue" then
    app.go("story", { level = app.save.unlocked })
  elseif id == "finale" then
    app.go("dragon", { char = "平" })
  elseif id == "help" then
    app.go("help")
  elseif id == "quit" then
    app.quit(0)
  end
end

function Title:mousepressed(x, y, b)
  if b ~= 1 then return end
  for _, bt in ipairs(self.buttons) do
    if G.inRect(x, y, bt) then self:activate(bt.id); return end
  end
end

function Title:keypressed(k)
  if k == "return" or k == "space" then self:activate(self.buttons[1].id)
  elseif k == "escape" then self:activate("quit") end
end

return Title
