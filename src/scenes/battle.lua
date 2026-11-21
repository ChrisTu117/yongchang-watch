-- SPDX-License-Identifier: AGPL-3.0-only
-- 守夜：地图、照明、操作、界面。规则在 src/sim/world.lua。
local love = require("love")
local U = require("src.util")
local G = require("src.gfx")
local A = require("src.audio")
local MAP = require("src.data.map")
local D = require("src.data.units")
local L = require("src.data.levels")
local World = require("src.sim.world")

local Battle = {}
Battle.__index = Battle

local TUT_TEXT = {
  [1] = "夜色深沉，海面一片漆黑。移动鼠标，把望楼的光照向东边的海面。",
  [2] = "海上有船！点击城墙上发光的敌台，花 3 点民力安排弓手。（按 1、2、3 可切换弓手、鸟铳、烽火）",
  [3] = "乡亲们从西边来投奔了！点击西门打开城门，迎他们进堡。每迎进一人，民力 +2。",
  [4] = "寇船在东边靠岸了！把光照向来犯者——守城单位只打得中看得见的敌人。迎完百姓，记得关上城门。",
  [5] = "守到天亮就算守住。空格暂停，Esc 打开菜单。城门被攻破后，点击它可以花民力修好。",
}

local WARM = { 1.0, 0.86, 0.62 }

function Battle.new(app, params)
  local s = setmetatable({ app = app, t = 0 }, Battle)
  s.levelIndex = params.level
  s.level = L[params.level]
  local skipTut = params.retry or (app.save.unlocked > 1)
  s.world = World.new(s.level, { skipTutorial = skipTut })
  s.selected = "archer"
  s.fx, s.parts = {}, {}
  s.shake = 0
  s.paused, s.menu, s.result = false, nil, nil
  s.resultDelay = 0
  s.tutDoneTimer = 0
  local ok, canvas = pcall(love.graphics.newCanvas, G.W, G.H)
  s.dark = ok and canvas or nil
  s.cards = {}
  for i, k in ipairs(D.towerOrder) do
    s.cards[i] = { kind = k, x = 12 + (i - 1) * 128, y = 503, w = 120, h = 32 }
  end
  s.lanternCard = { x = 12 + 3 * 128, y = 503, w = 120, h = 32 }
  A.playMusic("music_night")
  return s
end

----------------------------------------------------------------- 事件与特效
function Battle:float(text, x, y, color, size)
  self.fx[#self.fx + 1] = { text = text, x = x, y = y, t = 0, color = color or G.C.ink, size = size or 14 }
end

function Battle:burst(x, y, color, n)
  for _ = 1, n or 6 do
    local a = math.random() * math.pi * 2
    local v = 20 + math.random() * 50
    self.parts[#self.parts + 1] = { x = x, y = y, vx = math.cos(a) * v, vy = math.sin(a) * v, t = 0, c = color }
  end
end

function Battle:handleEvents()
  for _, e in ipairs(self.world:drainEvents()) do
    local ty = e.type
    if ty == "shoot" then
      A.play(e.kind == "gunner" and "gun" or "bow", e.kind == "gunner" and 0.45 or 0.3, 0.9 + math.random() * 0.2)
      if e.kind == "gunner" then self:burst(e.x, e.y, { 1, 0.85, 0.4 }, 4) end
    elseif ty == "hit" then
      A.play("hit", 0.25, 0.9 + math.random() * 0.3)
      self:burst(e.x, e.y, { 1, 0.9, 0.6 }, 3)
    elseif ty == "kill" then
      A.play("repel", 0.4)
      self:float("击退", e.x, e.y - 10, G.C.gold, 12)
      self:burst(e.x, e.y, { 0.9, 0.7, 0.4 }, 8)
    elseif ty == "gatehit" then
      A.play("gatehit", 0.45, 0.9 + math.random() * 0.2)
      self.shake = math.max(self.shake, 1.5)
    elseif ty == "breach" then
      A.play("breach", 0.8)
      self.shake = 8
      self:float(self.world.gateById[e.gate].name .. "被攻破！点击城门修复", e.x, e.y - 24, G.C.red, 16)
    elseif ty == "enter" then
      A.play("gatehit", 0.6, 0.6)
      self:float("堡安 -" .. U.int(e.harm), e.x, e.y - 14, G.C.red, 15)
      self.shake = math.max(self.shake, 3)
    elseif ty == "saved" then
      A.play("saved", 0.5)
      self:float("+" .. U.int(e.amount) .. " 民力", e.x, e.y - 14, G.C.green, 15)
    elseif ty == "scatter" then
      self:float("百姓被冲散", e.x, e.y - 10, G.C.dim, 12)
    elseif ty == "leave" then
      self:float("等不到开门，离开了", e.x, e.y - 10, G.C.dim, 12)
    elseif ty == "build" then
      A.play("build", 0.6)
      self:float(D.towers[e.kind].name, e.x, e.y - 18, G.C.gold, 13)
    elseif ty == "upgrade" then
      A.play("build", 0.6, 1.2)
      self:float(D.towers[e.kind].name .. " " .. U.int(e.level) .. " 级", e.x, e.y - 18, G.C.gold, 13)
    elseif ty == "maxlevel" then
      A.play("nomoney", 0.4)
      self:float("已是最高级", e.x, e.y - 18, G.C.dim, 12)
    elseif ty == "nomoney" then
      A.play("nomoney", 0.5)
      self:float("民力不足（需 " .. U.int(e.need) .. "）", e.x, e.y - 18, G.C.red, 13)
    elseif ty == "gateopen" or ty == "gateclose" then
      A.play("gate", 0.5, ty == "gateopen" and 1.0 or 0.85)
    elseif ty == "repair" then
      A.play("build", 0.7, 0.8)
      self:float("城门修好了", e.x, e.y - 18, G.C.green, 14)
    elseif ty == "lantern" then
      A.play("lantern", 0.6)
    elseif ty == "farm" then
      A.play("farm", 0.25)
      self:float("屯田 +1 民力", MAP.center.x, MAP.center.y - 26, G.C.green, 12)
    elseif ty == "tut" then
      A.play("tok", 0.6)
      print("[永昌守望] tutorial step " .. U.int(e.step))
    elseif ty == "won" then
      A.play("gong", 0.7)
    elseif ty == "lost" then
      A.play("breach", 0.8, 0.7)
    end
  end
end

----------------------------------------------------------------- 更新
function Battle:update(dt)
  self.t = self.t + dt
  if self.shake > 0 then self.shake = math.max(0, self.shake - dt * 12) end
  for i = #self.fx, 1, -1 do
    local f = self.fx[i]
    f.t = f.t + dt
    if f.t > 1.4 then table.remove(self.fx, i) end
  end
  for i = #self.parts, 1, -1 do
    local p = self.parts[i]
    p.t = p.t + dt
    p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    if p.t > 0.5 then table.remove(self.parts, i) end
  end
  if self.result then return end
  if self.paused or self.menu then return end
  local w = self.world
  w:update(dt)
  self:handleEvents()
  if w.tut and w.tut.step >= World.TUT.DONE then self.tutDoneTimer = self.tutDoneTimer + dt end
  if w.state ~= "playing" then
    self.resultDelay = self.resultDelay + dt
    if self.resultDelay > 1.2 then self:showResult() end
  end
end

function Battle:showResult()
  local w = self.world
  local won = w.state == "won"
  local stars = w:stars()
  if won then self.app.record(self.levelIndex, stars) end
  print("[永昌守望] night " .. U.int(self.levelIndex) .. (won and " won" or " lost"))
  local r = { won = won, stars = stars, buttons = {} }
  if won then
    r.buttons[1] = { id = "dragon", label = "舞龙显字：「" .. self.level.char .. "」", x = 380, y = 380, w = 200, h = 40 }
    r.buttons[2] = { id = "retry", label = "再守一次", x = 380, y = 430, w = 200, h = 34, size = 16 }
  else
    r.buttons[1] = { id = "retry", label = "再守一次", x = 380, y = 380, w = 200, h = 40 }
    r.buttons[2] = { id = "title", label = "返回标题", x = 380, y = 430, w = 200, h = 34, size = 16 }
  end
  self.result = r
end

----------------------------------------------------------------- 命中检测
function Battle:slotAt(x, y)
  for i, s in ipairs(self.world.slots) do
    if math.abs(x - s.x) <= 15 and math.abs(y - s.y) <= 15 then return i, s end
  end
end

function Battle:gateAt(x, y)
  for _, g in ipairs(self.world.gates) do
    if math.abs(x - g.x) <= 20 and math.abs(y - g.y) <= 20 then return g end
  end
end

----------------------------------------------------------------- 输入
function Battle:mousemoved(x, y)
  if not self.menu and not self.result then self.world:aim(x, y) end
end

function Battle:menuButtons()
  return {
    { id = "resume", label = "继续", x = 380, y = 170, w = 200, h = 40 },
    { id = "restart", label = "重新开始这一夜", x = 380, y = 220, w = 200, h = 40 },
    { id = "title", label = "返回标题", x = 380, y = 270, w = 200, h = 40 },
    { id = "quit", label = "退出游戏", x = 380, y = 320, w = 200, h = 40 },
  }
end

function Battle:activate(id)
  A.play("click")
  local app = self.app
  if id == "resume" then self.menu = nil
  elseif id == "restart" or id == "retry" then app.go("battle", { level = self.levelIndex, retry = true })
  elseif id == "title" then app.go("title")
  elseif id == "quit" then app.quit(0)
  elseif id == "dragon" then app.go("dragon", { char = self.level.char, level = self.levelIndex })
  end
end

function Battle:mousepressed(x, y, b)
  if self.result then
    for _, bt in ipairs(self.result.buttons) do if G.inRect(x, y, bt) then self:activate(bt.id); return end end
    return
  end
  if self.menu then
    for _, bt in ipairs(self:menuButtons()) do if G.inRect(x, y, bt) then self:activate(bt.id); return end end
    return
  end
  if b ~= 1 then return end
  for _, c in ipairs(self.cards) do
    if G.inRect(x, y, c) then self.selected = c.kind; A.play("click"); return end
  end
  if G.inRect(x, y, self.lanternCard) then return end
  if self.paused then return end
  local i = self:slotAt(x, y)
  if i then self.world:build(i, self.selected); return end
  local g = self:gateAt(x, y)
  if g then self.world:clickGate(g.id); return end
end

function Battle:keypressed(k)
  if self.result then
    if k == "return" or k == "space" then self:activate(self.result.buttons[1].id) end
    return
  end
  if k == "escape" then
    self.menu = (not self.menu) and true or nil
    A.play("click")
    return
  end
  if self.menu then return end
  if k == "space" then self.paused = not self.paused; A.play("click"); return end
  for _, c in ipairs(self.cards) do
    if k == D.towers[c.kind].key then self.selected = c.kind; A.play("click"); return end
  end
  if k == "f" and not self.paused then
    local mx, my = self.app.mouse()
    if not self.world:launchLantern(mx, my) then A.play("nomoney", 0.4) end
  end
end

----------------------------------------------------------------- 绘制：地形
local function shoreX(y) return MAP.shoreX + 14 * math.sin(y / 37) + 7 * math.sin(y / 13 + 1) end

function Battle:drawTerrain()
  local lg = love.graphics
  lg.setColor(0.17, 0.21, 0.15)
  lg.rectangle("fill", 0, 0, 960, 540)
  -- 田地
  lg.setColor(0.21, 0.27, 0.16)
  for _, r in ipairs({ { 140, 110, 120, 70 }, { 150, 360, 110, 80 }, { 600, 380, 120, 70 }, { 610, 90, 110, 60 },
                       { 330, 6, 200, 34 }, { 330, 500, 200, 34 } }) do
    lg.rectangle("fill", r[1], r[2], r[3], r[4])
  end
  lg.setColor(0.25, 0.31, 0.19)
  lg.setLineWidth(1)
  for _, r in ipairs({ { 140, 110, 120, 70 }, { 150, 360, 110, 80 }, { 600, 380, 120, 70 }, { 610, 90, 110, 60 } }) do
    for y = r[2] + 6, r[2] + r[4] - 2, 8 do lg.line(r[1] + 3, y, r[1] + r[3] - 3, y) end
  end
  -- 大罗山（西）
  lg.setColor(0.11, 0.16, 0.12)
  lg.polygon("fill", 0, 120, 60, 60, 120, 140, 70, 200, 0, 210)
  lg.polygon("fill", 0, 330, 50, 280, 110, 340, 80, 420, 0, 440)
  lg.setColor(0.14, 0.20, 0.15)
  lg.polygon("fill", 0, 160, 40, 110, 90, 170, 30, 200)
  lg.polygon("fill", 0, 370, 40, 320, 80, 380, 20, 420)
  -- 道路
  lg.setColor(0.29, 0.26, 0.19)
  lg.setLineWidth(7)
  lg.setLineJoin("bevel")
  for _, p in pairs(MAP.paths) do
    local v = {}
    for _, pt in ipairs(p.pts) do v[#v + 1] = pt[1]; v[#v + 1] = pt[2] end
    lg.line(v)
  end
  -- 海岸与海
  local sand, sea = {}, {}
  for y = 0, 540, 10 do sand[#sand + 1] = shoreX(y) - 8; sand[#sand + 1] = y end
  for y = 0, 540, 10 do sea[#sea + 1] = shoreX(y); sea[#sea + 1] = y end
  local function fillRight(pts, color)
    lg.setColor(color)
    for i = 1, #pts - 3, 2 do
      lg.polygon("fill", pts[i], pts[i + 1], 960, pts[i + 1], 960, pts[i + 3], pts[i + 2], pts[i + 3])
    end
  end
  fillRight(sand, { 0.36, 0.33, 0.24 })
  fillRight(sea, { 0.06, 0.13, 0.26 })
  lg.setColor(0.14, 0.26, 0.42, 0.7)
  lg.setLineWidth(1.2)
  for row = 0, 11 do
    local y0 = 20 + row * 45
    for col = 0, 4 do
      local x = shoreX(y0) + 30 + col * 38 + ((self.t * 12 + row * 17) % 38)
      if x < 955 then lg.arc("line", "open", x, y0 + math.sin(self.t + col) * 2, 8, math.pi * 1.1, math.pi * 1.9) end
    end
  end
  -- 护城河
  local f = MAP.fort
  lg.setColor(0.10, 0.24, 0.42)
  lg.setLineWidth(9)
  lg.rectangle("line", f.x1 - 16, f.y1 - 16, f.x2 - f.x1 + 32, f.y2 - f.y1 + 32)
  -- 堡内
  lg.setColor(0.25, 0.23, 0.18)
  lg.rectangle("fill", f.x1, f.y1, f.x2 - f.x1, f.y2 - f.y1)
  lg.setColor(0.24, 0.31, 0.18)
  for _, r in ipairs({ { 312, 225, 90, 95 }, { 458, 225, 90, 95 }, { 312, 350, 70, 88 }, { 478, 350, 70, 88 } }) do
    lg.rectangle("fill", r[1], r[2], r[3], r[4])
  end
  -- 上河、下河（穿过水门）
  lg.setColor(0.12, 0.30, 0.50)
  lg.setLineWidth(6)
  lg.line(f.x1 - 16, 205, f.x2 + 16, 205)
  lg.line(f.x1 - 16, 335, f.x2 + 16, 335)
  -- 民居
  lg.setColor(0.20, 0.15, 0.13)
  for row = 0, 2 do
    for col = 0, 5 do
      local x, y = 318 + col * 38, 104 + row * 30
      if not (col == 3 and row == 2) then lg.rectangle("fill", x, y, 26, 14) end
    end
  end
  for col = 0, 4 do
    if col ~= 2 then lg.rectangle("fill", 330 + col * 40, 410, 26, 14) end
  end
  lg.setColor(0.34, 0.24, 0.20)
  for row = 0, 2 do
    for col = 0, 5 do
      local x, y = 318 + col * 38, 104 + row * 30
      if not (col == 3 and row == 2) then lg.polygon("fill", x - 2, y + 2, x + 13, y - 5, x + 28, y + 2) end
    end
  end
  -- 望楼
  local c = MAP.center
  lg.setColor(0.36, 0.30, 0.24)
  lg.rectangle("fill", c.x - 14, c.y - 14, 28, 28)
  lg.setColor(0.45, 0.20, 0.15)
  lg.polygon("fill", c.x - 20, c.y - 10, c.x, c.y - 24, c.x + 20, c.y - 10)
  -- 城墙
  lg.setColor(0.52, 0.47, 0.39)
  lg.setLineWidth(9)
  lg.rectangle("line", f.x1, f.y1, f.x2 - f.x1, f.y2 - f.y1)
  lg.setColor(0.66, 0.60, 0.50)
  lg.setLineWidth(2)
  lg.rectangle("line", f.x1 + 3, f.y1 + 3, f.x2 - f.x1 - 6, f.y2 - f.y1 - 6)
  lg.setColor(0.45, 0.41, 0.34)
  for x = f.x1, f.x2, 12 do
    lg.rectangle("fill", x - 2, f.y1 - 8, 5, 4)
    lg.rectangle("fill", x - 2, f.y2 + 4, 5, 4)
  end
  for y = f.y1, f.y2, 12 do
    lg.rectangle("fill", f.x1 - 8, y - 2, 4, 5)
    lg.rectangle("fill", f.x2 + 4, y - 2, 4, 5)
  end
  -- 瓮城（东门外）
  lg.setColor(0.52, 0.47, 0.39)
  lg.setLineWidth(7)
  lg.arc("line", "open", f.x2, 270, 30, -math.pi / 2, math.pi / 2)
  -- 水门
  lg.setColor(0.06, 0.10, 0.16)
  for _, wg in ipairs(MAP.watergates) do lg.arc("fill", wg.x, wg.y + 3, 6, math.pi, math.pi * 2) end
end

----------------------------------------------------------------- 绘制：动态
function Battle:drawTower(s, hot)
  local lg = love.graphics
  local t = s.tower
  lg.setColor(0.42, 0.38, 0.32)
  lg.rectangle("fill", s.x - 11, s.y - 11, 22, 22, 2, 2)
  lg.setColor(0.60, 0.55, 0.46)
  lg.setLineWidth(1.5)
  lg.rectangle("line", s.x - 11, s.y - 11, 22, 22, 2, 2)
  if not t then
    local pulse = 0.35 + 0.25 * math.sin(self.t * 3 + s.i)
    local canAfford = self.world.minli >= D.towers[self.selected].cost
    lg.setColor(1, 0.85, 0.45, canAfford and pulse or 0.15)
    lg.setLineWidth(hot and 2.5 or 1.5)
    lg.rectangle("line", s.x - 8, s.y - 8, 16, 16)
    lg.line(s.x - 4, s.y, s.x + 4, s.y)
    lg.line(s.x, s.y - 4, s.x, s.y + 4)
    return
  end
  local aim = t.aim or 0
  if t.kind == "archer" then
    lg.setColor(0.55, 0.35, 0.18)
    lg.circle("fill", s.x, s.y, 7)
    lg.setColor(0.92, 0.82, 0.55)
    lg.setLineWidth(2)
    lg.arc("line", "open", s.x, s.y, 8, aim - 1.1, aim + 1.1)
    lg.setLineWidth(1)
    lg.line(s.x + math.cos(aim - 1.1) * 8, s.y + math.sin(aim - 1.1) * 8, s.x + math.cos(aim + 1.1) * 8, s.y + math.sin(aim + 1.1) * 8)
  elseif t.kind == "gunner" then
    lg.setColor(0.25, 0.22, 0.22)
    lg.circle("fill", s.x, s.y, 7)
    lg.setColor(0.75, 0.72, 0.68)
    lg.setLineWidth(3)
    lg.line(s.x, s.y, s.x + math.cos(aim) * 13, s.y + math.sin(aim) * 13)
  else
    lg.setColor(0.35, 0.25, 0.18)
    lg.polygon("fill", s.x - 8, s.y - 2, s.x + 8, s.y - 2, s.x + 5, s.y + 7, s.x - 5, s.y + 7)
    local fl = math.sin(self.t * 12 + s.i) * 2
    lg.setColor(1, 0.55, 0.15)
    lg.polygon("fill", s.x - 6, s.y - 2, s.x, s.y - 14 - fl, s.x + 6, s.y - 2)
    lg.setColor(1, 0.9, 0.4)
    lg.polygon("fill", s.x - 3, s.y - 2, s.x, s.y - 8 - fl, s.x + 3, s.y - 2)
  end
  for k = 1, t.level do
    lg.setColor(1, 0.8, 0.3)
    lg.circle("fill", s.x - 8 + (k - 1) * 8, s.y + 15, 2.2)
  end
end

function Battle:drawGate(g)
  local lg = love.graphics
  local horiz = (g.id == "N" or g.id == "S")
  local w, h = horiz and 28 or 11, horiz and 11 or 28
  lg.setColor(0.08, 0.07, 0.07)
  lg.rectangle("fill", g.x - w / 2, g.y - h / 2, w, h)
  if g.broken then
    lg.setColor(0.5, 0.2, 0.12)
    lg.setLineWidth(2)
    lg.line(g.x - w / 2, g.y - h / 2, g.x + w / 2, g.y + h / 2)
    lg.line(g.x + w / 2, g.y - h / 2, g.x - w / 2, g.y + h / 2)
  elseif g.open then
    lg.setColor(0.50, 0.32, 0.17)
    lg.setLineWidth(3)
    local out = ({ N = { 0, -1 }, S = { 0, 1 }, E = { 1, 0 }, W = { -1, 0 } })[g.id]
    if horiz then
      lg.line(g.x - w / 2, g.y, g.x - w / 2 + out[1] * 10, g.y + out[2] * 12)
      lg.line(g.x + w / 2, g.y, g.x + w / 2 + out[1] * 10, g.y + out[2] * 12)
    else
      lg.line(g.x, g.y - h / 2, g.x + out[1] * 12, g.y - h / 2)
      lg.line(g.x, g.y + h / 2, g.x + out[1] * 12, g.y + h / 2)
    end
  else
    local fl = g.flash > 0 and 0.3 or 0
    lg.setColor(0.48 + fl, 0.30, 0.16)
    lg.rectangle("fill", g.x - w / 2, g.y - h / 2, w, h)
    lg.setColor(0.75, 0.66, 0.45)
    for k = -1, 1 do
      if horiz then lg.circle("fill", g.x + k * 8, g.y, 1.5) else lg.circle("fill", g.x, g.y + k * 8, 1.5) end
    end
  end
end

function Battle:drawUnits()
  local lg = love.graphics
  local w = self.world
  for _, b in ipairs(w.boats) do
    local bob = math.sin(self.t * 2 + b.id) * 1.5
    lg.setColor(0.30, 0.20, 0.12)
    lg.polygon("fill", b.x - 16, b.y + bob, b.x + 14, b.y + bob, b.x + 9, b.y + 7 + bob, b.x - 11, b.y + 7 + bob)
    lg.setColor(0.52, 0.42, 0.32)
    lg.polygon("fill", b.x - 2, b.y - 20 + bob, b.x + 10, b.y - 16 + bob, b.x + 9, b.y - 2 + bob, b.x - 2, b.y - 2 + bob)
    lg.setColor(0.35, 0.28, 0.2)
    lg.setLineWidth(1)
    for k = 1, 3 do lg.line(b.x - 2, b.y - 20 + k * 5 + bob, b.x + 9.5, b.y - 17 + k * 5 + bob) end
  end
  for _, r in ipairs(w.refugees) do
    local x, y = r.x + r.ox * 0.6, r.y + r.oy * 0.6 + math.sin(self.t * 9 + r.id) * 0.8
    lg.setColor(0.78, 0.82, 0.88)
    lg.ellipse("fill", x, y + 2, 4, 5)
    lg.setColor(0.95, 0.85, 0.70)
    lg.circle("fill", x, y - 4, 2.6)
    lg.setColor(0.55, 0.40, 0.25)
    lg.circle("fill", x - 3.5, y, 2.6)
  end
  for _, e in ipairs(w.enemies) do
    local def = D.enemies[e.kind]
    local x, y = e.x + e.ox, e.y + e.oy
    local r = def.r
    lg.setColor(0.13, 0.11, 0.11)
    lg.circle("fill", x, y, r)
    lg.setColor(0.55, 0.16, 0.12)
    lg.rectangle("fill", x - r, y - 2, r * 2, 3)
    if e.kind == "brute" then
      lg.setColor(0.40, 0.36, 0.30)
      lg.rectangle("fill", x - r - 4, y - r, 4, r * 2)
    end
  end
  for _, sh in ipairs(w.shots) do
    if sh.kind == "gunner" then
      lg.setColor(1, 0.9, 0.5)
      lg.circle("fill", sh.x, sh.y, 2.2)
    else
      local e = w:findEnemy(sh.target)
      local a = e and U.atan2(e.y - sh.y, e.x - sh.x) or 0
      lg.setColor(0.95, 0.88, 0.65)
      lg.setLineWidth(1.5)
      lg.line(sh.x - math.cos(a) * 6, sh.y - math.sin(a) * 6, sh.x, sh.y)
    end
  end
  local lan = w.lantern
  if lan then
    local rise = (D.lantern.duration - lan.t) * 3
    lg.setColor(1, 0.7, 0.3)
    lg.rectangle("fill", lan.x - 5, lan.y - 8 - rise, 10, 13, 3, 3)
    lg.setColor(1, 0.95, 0.7)
    lg.rectangle("fill", lan.x - 2, lan.y - 2 - rise, 4, 3)
  end
end

----------------------------------------------------------------- 绘制：照明（望）
function Battle:ambient()
  local p = self.world:progress()
  local night = { 0.20, 0.22, 0.38 }
  local dawn = { 0.86, 0.78, 0.70 }
  local k = U.clamp((p - 0.85) / 0.15, 0, 1)
  return U.lerp(night[1], dawn[1], k), U.lerp(night[2], dawn[2], k), U.lerp(night[3], dawn[3], k)
end

function Battle:drawLighting()
  if not self.dark then return end
  local lg = love.graphics
  local w = self.world
  local sx, sy, sw, sh = lg.getScissor()
  lg.setScissor()
  lg.push()
  lg.origin()
  lg.setCanvas(self.dark)
  local ar, ag, ab = self:ambient()
  lg.clear(ar, ag, ab, 1)
  lg.setBlendMode("add")
  local img = G.lightImage()
  local function light(x, y, r, a)
    lg.setColor(WARM[1] * a, WARM[2] * a, WARM[3] * a, 1)
    local k = r * 2 / 128 * 1.25
    lg.draw(img, x, y, 0, k, k, 64, 64)
  end
  local f = MAP.fort
  lg.setColor(0.45, 0.40, 0.30, 1)
  lg.rectangle("fill", f.x1 - 4, f.y1 - 4, f.x2 - f.x1 + 8, f.y2 - f.y1 + 8)
  for _, s in ipairs(w.slots) do
    if s.tower then
      local flick = s.tower.kind == "beacon" and (0.95 + 0.05 * math.sin(self.t * 9 + s.i)) or 0.9
      light(s.x, s.y, w:towerStats(s.tower).light, flick)
    end
  end
  for _, g in ipairs(w.gates) do light(g.x, g.y, D.gateLight, 0.8) end
  if w.lantern then light(w.lantern.x, w.lantern.y, D.lantern.radius, 1.0) end
  local b = w.beam
  local layers = { { 1.3, 0.18 }, { 1.0, 0.35 }, { 0.6, 0.35 } }
  for _, l in ipairs(layers) do
    lg.setColor(0.95 * l[2], 0.90 * l[2], 0.70 * l[2], 1)
    lg.polygon("fill", G.fan(b.x, b.y, D.beam.len, b.angle - D.beam.half * l[1], b.angle + D.beam.half * l[1], 12))
  end
  lg.setCanvas()
  lg.pop()
  if sx then lg.setScissor(sx, sy, sw, sh) end
  lg.setBlendMode("multiply", "premultiplied")
  lg.setColor(1, 1, 1, 1)
  lg.draw(self.dark, 0, 0)
  lg.setBlendMode("alpha")
end

----------------------------------------------------------------- 绘制：叠加界面
function Battle:hoverInfo(mx, my)
  local w = self.world
  local i, s = self:slotAt(mx, my)
  if i then
    if not s.tower then
      local t = D.towers[self.selected]
      return string.format("空敌台：点击安排%s（%d 民力）。%s", t.name, t.cost, t.desc), s
    end
    local t = s.tower
    local def = D.towers[t.kind]
    if t.level >= D.maxLevel then return def.name .. " " .. U.int(t.level) .. " 级（最高级）", s end
    return string.format("%s %d 级：点击升级（%d 民力）", def.name, t.level, D.upgradeCost(t.kind, t.level)), s
  end
  local g = self:gateAt(mx, my)
  if g then
    local name = g.name .. (g.wengcheng and "（瓮城）" or "")
    if g.broken then return string.format("%s已被攻破：点击花 %d 民力修复", name, D.repairCost) end
    return string.format("%s 耐久 %d/%d：点击%s", name, math.floor(g.hp), math.floor(g.maxhp), g.open and "关门" or "开门")
  end
  return nil
end

function Battle:drawOverlay()
  local lg = love.graphics
  local w = self.world
  local mx, my = self.app.mouse()
  -- 城门状态
  for _, g in ipairs(w.gates) do
    if g.hp < g.maxhp and not g.broken then
      lg.setColor(0, 0, 0, 0.6)
      lg.rectangle("fill", g.x - 15, g.y - 24, 30, 4)
      lg.setColor(0.9, 0.5, 0.3)
      lg.rectangle("fill", g.x - 15, g.y - 24, 30 * g.hp / g.maxhp, 4)
    end
    if g.broken then G.outlined("破", g.x, g.y - 34, 14, G.C.red, "center") end
    local waiting, danger = 0, false
    for _, r in ipairs(w.refugees) do
      if MAP.paths[r.path].gate == g.id and r.d >= World.PATHLEN[r.path].total - 1 then waiting = waiting + 1 end
    end
    for _, e in ipairs(w.enemies) do
      if MAP.paths[e.path].gate == g.id and (e.remain or 999) < 90 and e.lit then danger = true end
    end
    if waiting > 0 and not g.open then
      local bob = math.sin(self.t * 5) * 2
      local bx, by = g.fx + (g.id == "W" and -26 or (g.id == "E" and 26 or 0)), g.fy + (g.id == "N" and -20 or (g.id == "S" and 20 or 0)) + bob
      G.panel(bx - 34, by - 11, 68, 22, 0.85)
      G.text("开门！×" .. U.int(waiting), bx, by - 8, 12, G.C.green, "center")
    end
    if danger and g.open and math.floor(self.t * 4) % 2 == 0 then G.outlined("！敌近", g.x, g.y + 14, 13, G.C.red, "center") end
  end
  -- 敌人血条（只有看得见的）
  for _, e in ipairs(w.enemies) do
    if e.lit and e.hp < e.maxhp then
      lg.setColor(0, 0, 0, 0.6)
      lg.rectangle("fill", e.x - 8, e.y - 14, 16, 3)
      lg.setColor(0.9, 0.3, 0.25)
      lg.rectangle("fill", e.x - 8, e.y - 14, 16 * math.max(0, e.hp) / e.maxhp, 3)
    end
  end
  -- 悬停：射程与高亮
  if not self.menu and not self.result then
    local i, s = self:slotAt(mx, my)
    if i then
      local range = s.tower and w:towerStats(s.tower).range or D.towers[self.selected].range
      if range > 0 then
        lg.setColor(1, 0.85, 0.5, 0.35)
        lg.setLineWidth(1)
        lg.circle("line", s.x, s.y, range)
      end
      lg.setColor(1, 0.9, 0.5, 0.9)
      lg.setLineWidth(2)
      lg.rectangle("line", s.x - 13, s.y - 13, 26, 26)
    end
    local g = self:gateAt(mx, my)
    if g then
      lg.setColor(1, 0.9, 0.5, 0.9)
      lg.setLineWidth(2)
      lg.circle("line", g.x, g.y, 18)
    end
  end
  -- 粒子与飘字
  for _, p in ipairs(self.parts) do
    lg.setColor(p.c[1], p.c[2], p.c[3], 1 - p.t / 0.5)
    lg.circle("fill", p.x, p.y, 1.6)
  end
  for _, f in ipairs(self.fx) do
    local a = 1 - math.max(0, f.t - 0.8) / 0.6
    local c = f.color
    G.outlined(f.text, f.x, f.y - f.t * 18, f.size, { c[1], c[2], c[3], a }, "center")
  end
end

function Battle:drawTutorial()
  local w = self.world
  local step
  if w:tutorialActive() then step = w.tut.step
  elseif w.tut and self.tutDoneTimer < 7 then step = 5 end
  if not step then return end
  local lg = love.graphics
  local _, lines = G.text(TUT_TEXT[step], -1000, -1000, 15, G.C.ink, "left", 250, 1.4)
  local ph = #lines * 15 * 1.4 + 18
  G.panel(10, 46, 274, ph, 0.92)
  G.text(TUT_TEXT[step], 22, 54, 15, G.C.ink, "left", 250, 1.4)
  local target
  if step == 1 then target = { 870, 270 }
  elseif step == 2 then
    local s = w.slots[5]
    target = { s.x, s.y }
  elseif step == 3 then target = { w.gateById.W.x, w.gateById.W.y }
  elseif step == 4 then target = { 760, 270 } end
  if target then
    local pulse = 14 + 6 * math.sin(self.t * 6)
    lg.setColor(1, 0.85, 0.4, 0.9)
    lg.setLineWidth(2.5)
    lg.circle("line", target[1], target[2], pulse)
    lg.setLineWidth(1.5)
    lg.setColor(1, 0.85, 0.4, 0.6)
    lg.line(284, 46 + ph / 2, target[1] - pulse, target[2])
  end
end

function Battle:drawHUD()
  local lg = love.graphics
  local w = self.world
  lg.setColor(0.05, 0.05, 0.08, 0.88)
  lg.rectangle("fill", 0, 0, 960, 38)
  G.text(self.level.title, 12, 4, 17, G.C.gold, "left")
  G.text(self.level.era .. " · " .. self.level.foe, 12, 23, 11, G.C.dim, "left")
  -- 天亮进度
  local bx, by, bw = 300, 9, 300
  lg.setColor(0.15, 0.15, 0.25)
  lg.rectangle("fill", bx, by, bw, 9, 4, 4)
  lg.setColor(0.95, 0.75, 0.40)
  lg.rectangle("fill", bx, by, bw * w:progress(), 9, 4, 4)
  lg.setColor(0.9, 0.9, 0.8)
  lg.circle("fill", bx - 10, by + 4.5, 5)
  lg.setColor(1, 0.7, 0.3)
  lg.circle("fill", bx + bw + 10, by + 4.5, 5)
  local left = math.max(0, w.duration - w.t)
  G.text(w:tutorialActive() and "教学中，天亮计时暂停" or ("距天亮 " .. U.int(left) .. " 秒"), bx + bw / 2, 21, 11, G.C.dim, "center")
  -- 资源
  G.text("民力", 650, 5, 13, G.C.dim, "left")
  G.text(U.int(w.minli), 684, 1, 22, G.C.gold, "left")
  G.text("堡安", 730, 5, 13, G.C.dim, "left")
  lg.setColor(0.2, 0.1, 0.1)
  lg.rectangle("fill", 764, 10, 80, 9, 3, 3)
  local an = w.anning / D.anning
  lg.setColor(an > 0.5 and 0.45 or 0.9, an > 0.5 and 0.8 or 0.35, 0.4)
  lg.rectangle("fill", 764, 10, 80 * an, 9, 3, 3)
  G.text(U.int(w.anning), 804, 21, 10, G.C.dim, "center")
  G.text("迎入 " .. U.int(w.saved), 856, 5, 13, G.C.green, "left")
  -- 底栏
  lg.setColor(0.05, 0.05, 0.08, 0.88)
  lg.rectangle("fill", 0, 498, 960, 42)
  for _, c in ipairs(self.cards) do
    local t = D.towers[c.kind]
    local sel = self.selected == c.kind
    local afford = w.minli >= t.cost
    lg.setColor(sel and 0.45 or 0.18, sel and 0.18 or 0.12, sel and 0.12 or 0.1, 0.95)
    lg.rectangle("fill", c.x, c.y, c.w, c.h, 4, 4)
    G.setColor(sel and G.C.gold or G.C.panelEdge)
    lg.setLineWidth(sel and 2 or 1)
    lg.rectangle("line", c.x + 0.5, c.y + 0.5, c.w - 1, c.h - 1, 4, 4)
    G.text(t.key, c.x + 8, c.y + 8, 12, G.C.dim, "left")
    G.text(t.name, c.x + 24, c.y + 5, 17, afford and G.C.ink or G.C.dim, "left")
    G.text(U.int(t.cost) .. " 民力", c.x + c.w - 8, c.y + 9, 12, afford and G.C.gold or G.C.red, "right")
  end
  local lc = self.lanternCard
  lg.setColor(0.18, 0.12, 0.1, 0.95)
  lg.rectangle("fill", lc.x, lc.y, lc.w, lc.h, 4, 4)
  if w.lanternCd > 0 then
    lg.setColor(0.4, 0.3, 0.2, 0.9)
    lg.rectangle("fill", lc.x, lc.y, lc.w * (1 - w.lanternCd / D.lantern.cooldown), lc.h, 4, 4)
  end
  G.text("F", lc.x + 8, lc.y + 8, 12, G.C.dim, "left")
  G.text("孔明灯", lc.x + 24, lc.y + 5, 17, w.lanternCd > 0 and G.C.dim or G.C.ink, "left")
  local mx, my = self.app.mouse()
  local info = self:hoverInfo(mx, my) or "移动鼠标照亮黑暗；点敌台安排守城单位；点城门开关。空格暂停，Esc 菜单。"
  G.text(info, 532, 508, 12, G.C.dim, "left", 420, 1.3)
end

function Battle:drawMenu()
  local lg = love.graphics
  lg.setColor(0, 0, 0, 0.6)
  lg.rectangle("fill", 0, 0, 960, 540)
  G.panel(340, 110, 280, 270)
  G.text("暂停", 480, 124, 24, G.C.gold, "center")
  local mx, my = self.app.mouse()
  for _, b in ipairs(self:menuButtons()) do G.button(b, G.inRect(mx, my, b)) end
end

function Battle:drawResult()
  local lg = love.graphics
  local r = self.result
  local w = self.world
  lg.setColor(0, 0, 0, 0.55)
  lg.rectangle("fill", 0, 0, 960, 540)
  G.panel(290, 110, 380, 370)
  G.text(r.won and "天亮了，守住了！" or "城堡失守……", 480, 130, 30, r.won and G.C.gold or G.C.red, "center")
  if r.won then
    for k = 1, 3 do G.star(430 + (k - 1) * 50, 200, 16, k <= r.stars) end
  end
  local lines = {
    "堡安：" .. U.int(w.anning) .. " / " .. U.int(D.anning),
    "迎入百姓：" .. U.int(w.saved) .. " / " .. U.int(w.refugeesSpawned),
    "击退来犯：" .. U.int(w.kills),
  }
  for i, l in ipairs(lines) do G.text(l, 480, 236 + (i - 1) * 28, 18, G.C.ink, "center") end
  if not r.won then G.text("提示：用光照着敌人，塔才打得中；敌人靠近时关好城门。", 480, 330, 13, G.C.dim, "center", 340) end
  local mx, my = self.app.mouse()
  for _, b in ipairs(r.buttons) do G.button(b, G.inRect(mx, my, b)) end
end

function Battle:draw()
  local lg = love.graphics
  lg.push()
  if self.shake > 0 then
    lg.translate((math.random() - 0.5) * self.shake, (math.random() - 0.5) * self.shake)
  end
  self:drawTerrain()
  local mx, my = self.app.mouse()
  local hot = self:slotAt(mx, my)
  for i, s in ipairs(self.world.slots) do self:drawTower(s, hot == i) end
  for _, g in ipairs(self.world.gates) do self:drawGate(g) end
  self:drawUnits()
  self:drawLighting()
  if self.coverMode then
    lg.pop()
    lg.setColor(0, 0, 0, 0.45)
    lg.rectangle("fill", 0, 0, 960, 150)
    G.text("永昌守望", 480, 18, 64, G.C.gold, "center")
    G.text("守 · 望　　一座古堡，三夜守望，拼出天下太平", 480, 104, 18, G.C.ink, "center")
    return
  end
  self:drawOverlay()
  lg.pop()
  self:drawTutorial()
  self:drawHUD()
  if self.paused and not self.menu then
    G.panel(400, 240, 160, 50)
    G.text("暂停中", 480, 252, 20, G.C.gold, "center")
  end
  if self.menu then self:drawMenu() end
  if self.result then self:drawResult() end
end

return Battle
