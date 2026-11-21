-- SPDX-License-Identifier: AGPL-3.0-only
-- 舞龙显字：按笔顺用龙描字。拼字龙灯的龙头、七节龙身、龙尾各自独立，这里共九节。
local love = require("love")
local U = require("src.util")
local G = require("src.gfx")
local A = require("src.audio")
local S = require("src.data.strokes")
local Story = require("src.data.story")
local Stroke = require("src.sim.stroke")
local L = require("src.data.levels")

local Scene = {}
Scene.__index = Scene

local BOX = { x = 470, y = 110, s = 330 }   -- 田字格位置与边长（逻辑坐标）
local SEGMENTS = 9                          -- 龙头 + 七节龙身 + 龙尾
local GAP = 15

local REASON = {
  short = "这一笔太短了，按住鼠标拖完整。",
  start = "起笔不对：从发光的圆点开始。",
  ["end"] = "收笔不对：一直写到箭头所指的位置。",
  reverse = "方向反了：顺着箭头的方向写。",
  shape = "形状偏了一些，再试一次。",
}

function Scene.new(app, params)
  local s = setmetatable({ app = app, t = 0, char = params.char, level = params.level }, Scene)
  s.def = S[s.char]
  s.session = Stroke.session(s.def)
  s.drawing = nil
  s.msg, s.msgColor, s.msgT = nil, G.C.ink, 0
  s.shake = 0
  s.doneT = nil
  s.segs = {}
  for i = 1, SEGMENTS do s.segs[i] = { x = BOX.x + BOX.s / 2, y = BOX.y + BOX.s + 30 + i * GAP } end
  s.assistBtn = { x = 210, y = 430, w = 160, h = 34, label = "请师傅带一笔", size = 15 }
  s.nextBtn = { x = 210, y = 470, w = 160, h = 38, label = "继续" }
  A.playMusic("music_festival")
  return s
end

function Scene:toUnit(x, y) return (x - BOX.x) / BOX.s, (y - BOX.y) / BOX.s end
function Scene:fromUnit(u, v) return BOX.x + u * BOX.s, BOX.y + v * BOX.s end

function Scene:say(text, color)
  self.msg, self.msgColor, self.msgT = text, color or G.C.ink, 0
end

-- 龙身跟随龙头
function Scene:follow(hx, hy)
  local segs = self.segs
  segs[1].x, segs[1].y = hx, hy
  for i = 2, #segs do
    local a, b = segs[i - 1], segs[i]
    local d = U.dist(a.x, a.y, b.x, b.y)
    if d > GAP then
      local k = (d - GAP) / d
      b.x = b.x + (a.x - b.x) * k
      b.y = b.y + (a.y - b.y) * k
    end
  end
end

function Scene:update(dt)
  self.t = self.t + dt
  self.msgT = self.msgT + dt
  if self.shake > 0 then self.shake = math.max(0, self.shake - dt * 20) end
  if self.drawing then
    local mx, my = self.app.mouse()
    self:follow(mx, my)
  elseif not self.doneT then
    -- 没在写的时候，龙在格子下方游动
    local x = BOX.x + BOX.s / 2 + math.sin(self.t * 1.3) * 120
    local y = BOX.y + BOX.s + 50 + math.sin(self.t * 2.6) * 14
    self:follow(U.lerp(self.segs[1].x, x, math.min(1, dt * 4)), U.lerp(self.segs[1].y, y, math.min(1, dt * 4)))
  else
    -- 写完了：龙绕着字盘旋
    local a = self.t * 1.6
    self:follow(BOX.x + BOX.s / 2 + math.cos(a) * (BOX.s * 0.62), BOX.y + BOX.s / 2 + math.sin(a) * (BOX.s * 0.62))
  end
end

function Scene:mousepressed(x, y, b)
  if b ~= 1 then return end
  if self.doneT then
    if G.inRect(x, y, self.nextBtn) then self:finish() end
    return
  end
  if self.session.fails >= 3 and G.inRect(x, y, self.assistBtn) then
    self.session:assist()
    A.play("drum", 0.6, 0.9)
    self:say("师傅带了一笔。", G.C.dim)
    self:checkDone()
    return
  end
  local u, v = self:toUnit(x, y)
  if u >= -0.1 and u <= 1.1 and v >= -0.1 and v <= 1.1 then
    self.drawing = { { u, v } }
    self:follow(x, y)
  end
end

function Scene:mousemoved(x, y)
  if not self.drawing then return end
  local u, v = self:toUnit(x, y)
  local last = self.drawing[#self.drawing]
  if U.dist(last[1], last[2], u, v) > 0.008 then self.drawing[#self.drawing + 1] = { u, v } end
end

function Scene:mousereleased(x, y, b)
  if b ~= 1 or not self.drawing then return end
  self:mousemoved(x, y)
  local drawn = self.drawing
  self.drawing = nil
  local name = self.session:current().name
  local ok, info = self.session:submit(drawn)
  if ok then
    A.play("drum", 0.8)
    self:say(name .. "，好！", G.C.gold)
    self:checkDone()
  else
    A.play("tok", 0.6, 0.7)
    self.shake = 6
    local extra = self.session.fails >= 3 and "（也可以请师傅带一笔）" or ""
    self:say((REASON[info.reason] or "再试一次。") .. extra, G.C.red)
  end
end

function Scene:checkDone()
  if self.session:finished() and not self.doneT then
    self.doneT = self.t
    A.play("gong", 0.8)
    self:say("「" .. self.char .. "」字拼成了！", G.C.gold)
  end
end

function Scene:finish()
  A.play("click")
  local app = self.app
  local lv = self.level
  if self.char == "平" then
    if app.save.unlocked < 4 then app.save.unlocked = 4; app.writeSave() end
    app.go("ending")
  elseif lv and lv < L.count then
    app.go("story", { level = lv + 1 })
  else
    app.go("dragon", { char = "平", level = L.count + 1 })
  end
end

function Scene:keypressed(k)
  if self.doneT and (k == "return" or k == "space") then self:finish()
  elseif k == "h" and self.session.fails >= 3 and not self.doneT then
    self:mousepressed(self.assistBtn.x + 1, self.assistBtn.y + 1, 1)
  elseif k == "escape" then self.app.go("title") end
end

----------------------------------------------------------------- 绘制
local function brush(pts, toScreen, width, color)
  local lg = love.graphics
  lg.setColor(color)
  lg.setLineWidth(width)
  lg.setLineJoin("bevel")
  local v = {}
  for _, p in ipairs(pts) do
    local x, y = toScreen(p[1], p[2])
    v[#v + 1] = x; v[#v + 1] = y
  end
  if #v >= 4 then lg.line(v) end
  for i = 1, #v, 2 do lg.circle("fill", v[i], v[i + 1], width / 2) end
end

function Scene:drawDragon()
  local lg = love.graphics
  local c = self.def.color
  local segs = self.segs
  for i = #segs, 1, -1 do
    local s = segs[i]
    local r = (i == 1) and 15 or ((i == #segs) and 8 or 12 - (i - 2) * 0.4)
    if i == #segs then
      lg.setColor(c[1] * 0.8, c[2] * 0.8, c[3] * 0.8)
      local p = segs[i - 1]
      local a = U.atan2(s.y - p.y, s.x - p.x)
      lg.polygon("fill", s.x + math.cos(a + 1.2) * 10, s.y + math.sin(a + 1.2) * 10,
        s.x + math.cos(a) * 18, s.y + math.sin(a) * 18, s.x + math.cos(a - 1.2) * 10, s.y + math.sin(a - 1.2) * 10)
    end
    -- 龙身下的竿子（舞龙人举着）
    lg.setColor(0.35, 0.25, 0.15)
    lg.setLineWidth(2)
    lg.line(s.x, s.y + r * 0.6, s.x, s.y + r + 16)
    lg.setColor(c)
    lg.circle("fill", s.x, s.y, r)
    lg.setColor(1, 0.85, 0.4)
    lg.setLineWidth(1.5)
    lg.arc("line", "open", s.x, s.y, r * 0.65, math.pi * 0.15, math.pi * 0.85)
  end
  local h, n = segs[1], segs[2]
  local a = U.atan2(h.y - n.y, h.x - n.x)
  local function at(d, side) return h.x + math.cos(a) * d + math.cos(a + math.pi / 2) * side, h.y + math.sin(a) * d + math.sin(a + math.pi / 2) * side end
  lg.setColor(1, 0.85, 0.35)
  local x1, y1 = at(-4, -9); local x2, y2 = at(-16, -16)
  lg.setLineWidth(2.5); lg.line(x1, y1, x2, y2)
  x1, y1 = at(-4, 9); x2, y2 = at(-16, 16)
  lg.line(x1, y1, x2, y2)
  lg.setColor(1, 1, 1)
  x1, y1 = at(6, -6); lg.circle("fill", x1, y1, 3.5)
  x2, y2 = at(6, 6); lg.circle("fill", x2, y2, 3.5)
  lg.setColor(0, 0, 0)
  lg.circle("fill", x1, y1, 1.6); lg.circle("fill", x2, y2, 1.6)
  lg.setColor(1, 0.9, 0.5)
  lg.setLineWidth(1.5)
  x1, y1 = at(14, -4); x2, y2 = at(26, -12 + math.sin(self.t * 5) * 3)
  lg.line(x1, y1, x2, y2)
  x1, y1 = at(14, 4); x2, y2 = at(26, 12 + math.sin(self.t * 5 + 1) * 3)
  lg.line(x1, y1, x2, y2)
end

function Scene:draw()
  local lg = love.graphics
  lg.setColor(0.22, 0.05, 0.05)
  lg.rectangle("fill", 0, 0, 960, 540)
  -- 灯笼
  for i = 0, 11 do
    local x = 40 + i * 80
    local y = 26 + math.sin(self.t * 1.5 + i) * 3
    lg.setColor(0.4, 0.3, 0.2)
    lg.setLineWidth(1)
    lg.line(x, 0, x, y - 10)
    lg.setColor(0.95, 0.25, 0.15)
    lg.ellipse("fill", x, y, 13, 11)
    lg.setColor(1, 0.8, 0.3)
    lg.rectangle("fill", x - 5, y + 10, 10, 3)
  end
  G.text("舞龙显字", 40, 64, 30, G.C.gold, "left")
  G.text(self.def.dragon .. " · 「" .. self.char .. "」", 40, 108, 20, G.C.ink, "left")
  local story = Story.dragon[self.char]
  G.text(story.text, 40, 146, 15, { 0.95, 0.88, 0.78 }, "left", 380, 1.6)
  if story.src then G.text("出处 [" .. story.src .. "]", 40, 400, 11, G.C.dim, "left") end

  lg.push()
  if self.shake > 0 then lg.translate((math.random() - 0.5) * self.shake, 0) end
  -- 田字格
  lg.setColor(0.98, 0.93, 0.82)
  lg.rectangle("fill", BOX.x, BOX.y, BOX.s, BOX.s)
  lg.setColor(0.75, 0.25, 0.2)
  lg.setLineWidth(3)
  lg.rectangle("line", BOX.x, BOX.y, BOX.s, BOX.s)
  lg.setLineWidth(1)
  lg.setColor(0.85, 0.5, 0.45)
  for k = 1, 30 do
    local t0, t1 = (k - 1) / 30, (k - 0.5) / 30
    lg.line(BOX.x + BOX.s / 2, BOX.y + BOX.s * t0, BOX.x + BOX.s / 2, BOX.y + BOX.s * t1)
    lg.line(BOX.x + BOX.s * t0, BOX.y + BOX.s / 2, BOX.x + BOX.s * t1, BOX.y + BOX.s / 2)
  end
  local toS = function(u, v) return self:fromUnit(u, v) end
  -- 字的影子
  for _, st in ipairs(self.def.strokes) do brush(st.pts, toS, 20, { 0.88, 0.82, 0.72 }) end
  -- 已完成的笔画
  local c = self.def.color
  for i = 1, self.session.idx - 1 do
    brush(self.def.strokes[i].pts, toS, 22, { c[1], c[2], c[3] })
  end
  -- 当前笔画提示
  local cur = self.session:current()
  if cur then
    brush(cur.pts, toS, 22, { 1, 0.75, 0.3, 0.45 + 0.2 * math.sin(self.t * 4) })
    local sx, sy = toS(cur.pts[1][1], cur.pts[1][2])
    lg.setColor(1, 0.6, 0.1)
    lg.circle("fill", sx, sy, 8 + math.sin(self.t * 6) * 2)
    -- 移动的引导点
    local k = (self.t * 0.6) % 1
    local path = U.resample(cur.pts, 20)
    local p = path[math.max(1, math.min(20, math.floor(k * 19) + 1))]
    local gx, gy = toS(p[1], p[2])
    lg.setColor(0.6, 0.1, 0.05, 0.8)
    lg.circle("fill", gx, gy, 4)
    -- 终点箭头
    local z, y2 = cur.pts[#cur.pts], cur.pts[#cur.pts - 1]
    local zx, zy = toS(z[1], z[2])
    local px, py = toS(y2[1], y2[2])
    local a = U.atan2(zy - py, zx - px)
    lg.setColor(0.6, 0.1, 0.05)
    lg.polygon("fill", zx + math.cos(a) * 12, zy + math.sin(a) * 12,
      zx + math.cos(a + 2.5) * 10, zy + math.sin(a + 2.5) * 10, zx + math.cos(a - 2.5) * 10, zy + math.sin(a - 2.5) * 10)
  end
  -- 正在写的这一笔
  if self.drawing then brush(self.drawing, toS, 14, { c[1], c[2], c[3], 0.8 }) end
  lg.pop()
  self:drawDragon()

  local total = #self.def.strokes
  if cur then
    G.text(string.format("第 %d 笔 / 共 %d 笔：%s", self.session.idx, total, cur.name), BOX.x + BOX.s / 2, BOX.y - 34, 18, G.C.ink, "center")
  end
  if self.msg then
    local a = self.msgT < 3 and 1 or math.max(0, 1 - (self.msgT - 3))
    G.text(self.msg, BOX.x + BOX.s / 2, BOX.y + BOX.s + 70, 16, { self.msgColor[1], self.msgColor[2], self.msgColor[3], a }, "center")
  end
  local mx, my = self.app.mouse()
  if self.doneT then
    G.text("「" .. self.char .. "」", 210 + 80, 330, 64, G.C.gold, "center")
    G.button(self.nextBtn, G.inRect(mx, my, self.nextBtn))
  elseif self.session.fails >= 3 then
    G.button(self.assistBtn, G.inRect(mx, my, self.assistBtn))
  else
    G.text("按住鼠标左键，从发光的圆点起笔，顺着箭头写。", 40, 440, 13, G.C.dim, "left", 380)
  end
end

return Scene
