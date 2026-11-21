-- SPDX-License-Identifier: AGPL-3.0-only
-- 终章：五龙同舞，拼出“天下太平”。
local love = require("love")
local G = require("src.gfx")
local A = require("src.audio")
local Story = require("src.data.story")

local Scene = {}
Scene.__index = Scene

local DRAGONS = {
  { 0.86, 0.22, 0.18 }, { 0.93, 0.74, 0.20 }, { 0.25, 0.48, 0.86 }, { 0.24, 0.66, 0.40 }, { 0.15, 0.15, 0.17 },
}
local CHARS = { "天", "下", "太", "平" }

function Scene.new(app)
  local s = setmetatable({ app = app, t = 0, page = 1 }, Scene)
  s.btn = { x = 400, y = 448, w = 160, h = 36, label = "返回标题" }
  A.playMusic("music_festival")
  A.play("gong", 0.8)
  return s
end

function Scene:update(dt)
  self.t = self.t + dt
  local p = math.min(#Story.ending, 1 + math.floor(self.t / 4))
  if p ~= self.page then self.page = p; A.play("drum", 0.6) end
end

function Scene:draw()
  local lg = love.graphics
  lg.setColor(0.20, 0.05, 0.05)
  lg.rectangle("fill", 0, 0, 960, 540)
  for d, c in ipairs(DRAGONS) do
    local baseY = 270 + (d - 3) * 22
    for i = 9, 1, -1 do
      local x = ((self.t * 90 + d * 170 - i * 16) % 1160) - 100
      local y = baseY + math.sin(self.t * 2 + d + i * 0.5) * 16
      lg.setColor(c[1], c[2], c[3], 0.9)
      lg.circle("fill", x, y, i == 1 and 12 or 9)
      lg.setColor(1, 0.85, 0.4, 0.8)
      lg.setLineWidth(1)
      lg.arc("line", "open", x, y, 6, 0.4, 2.7)
    end
  end
  for i, ch in ipairs(CHARS) do
    local appear = math.min(1, math.max(0, (self.t - (i - 1) * 0.7) / 0.6))
    if appear > 0 then G.text(ch, 270 + (i - 1) * 140, 70, 96, { 1, 0.82, 0.36, appear }, "center") end
  end
  local p = Story.ending[self.page]
  G.text(p.head, 480, 352, 22, G.C.gold, "center")
  G.text(p.text, 480, 386, 16, G.C.ink, "center", 700)
  G.text(Story.credits, 480, 498, 10, G.C.dim, "center", 860, 1.3)
  local mx, my = self.app.mouse()
  if self.t > 2 then G.button(self.btn, G.inRect(mx, my, self.btn)) end
end

function Scene:mousepressed(x, y, b)
  if b == 1 and self.t > 2 and G.inRect(x, y, self.btn) then A.play("click"); self.app.go("title") end
end

function Scene:keypressed(k)
  if k == "escape" or k == "return" then self.app.go("title") end
end

return Scene
