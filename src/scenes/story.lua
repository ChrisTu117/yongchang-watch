-- SPDX-License-Identifier: AGPL-3.0-only
-- 每夜开始前的剧情页。点击或空格翻页。
local love = require("love")
local G = require("src.gfx")
local A = require("src.audio")
local L = require("src.data.levels")
local Story = require("src.data.story")

local Scene = {}
Scene.__index = Scene

function Scene.new(app, params)
  local s = setmetatable({ app = app, level = params.level, page = 1, t = 0 }, Scene)
  s.pages = Story.before[params.level]
  A.playMusic("music_night")
  return s
end

function Scene:update(dt) self.t = self.t + dt end

function Scene:draw()
  love.graphics.setColor(0.05, 0.06, 0.10)
  love.graphics.rectangle("fill", 0, 0, 960, 540)
  -- 卷轴底
  love.graphics.setColor(0.80, 0.72, 0.56)
  love.graphics.rectangle("fill", 150, 110, 660, 320, 4, 4)
  love.graphics.setColor(0.42, 0.24, 0.14)
  love.graphics.rectangle("fill", 136, 100, 14, 340, 4, 4)
  love.graphics.rectangle("fill", 810, 100, 14, 340, 4, 4)
  local lv = L[self.level]
  G.text(lv.title, 480, 40, 34, G.C.gold, "center")
  G.text(lv.era, 480, 82, 16, G.C.dim, "center")
  local p = self.pages[self.page]
  local fade = math.min(1, self.t * 3)
  G.text(p.head, 190, 140, 26, { 0.45, 0.13, 0.10, fade }, "left")
  G.text(p.text, 190, 196, 21, { 0.16, 0.11, 0.08, fade }, "left", 580, 1.6)
  if p.src then G.text("史料出处 [" .. p.src .. "]，见 docs/文化资料与出处.md", 790, 400, 11, { 0.35, 0.28, 0.2 }, "right") end
  G.text(string.format("%d / %d", self.page, #self.pages), 480, 450, 14, G.C.dim, "center")
  local blink = 0.5 + 0.5 * math.sin(self.t * 4)
  G.text(self.page < #self.pages and "点击或按空格继续" or "点击或按空格，开始守夜", 480, 480, 16, { 1, 0.85, 0.5, 0.5 + 0.5 * blink }, "center")
  G.text("Esc 跳过", 948, 516, 12, G.C.dim, "right")
end

function Scene:next()
  A.play("click")
  if self.page < #self.pages then
    self.page = self.page + 1
    self.t = 0
  else
    self.app.go("battle", { level = self.level })
  end
end

function Scene:mousepressed(_, _, b) if b == 1 then self:next() end end

function Scene:keypressed(k)
  if k == "space" or k == "return" then self:next()
  elseif k == "escape" then self.app.go("battle", { level = self.level }) end
end

return Scene
