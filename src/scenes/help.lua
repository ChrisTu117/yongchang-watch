-- SPDX-License-Identifier: AGPL-3.0-only
local love = require("love")
local G = require("src.gfx")
local A = require("src.audio")
local Story = require("src.data.story")
local D = require("src.data.units")

local Scene = {}
Scene.__index = Scene

function Scene.new(app)
  return setmetatable({ app = app, back = { x = 400, y = 470, w = 160, h = 40, label = "返回" } }, Scene)
end

function Scene:draw()
  love.graphics.setColor(0.05, 0.06, 0.10)
  love.graphics.rectangle("fill", 0, 0, 960, 540)
  G.text("操作说明", 480, 30, 32, G.C.gold, "center")
  local y = 90
  for i, line in ipairs(Story.help) do
    local h = G.text(i .. ". " .. line, 120, y, 18, G.C.ink, "left", 720)
    y = y + h + 8
  end
  y = y + 6
  G.text("守城单位", 120, y, 20, G.C.gold, "left")
  y = y + 32
  for _, k in ipairs(D.towerOrder) do
    local t = D.towers[k]
    local h = G.text(string.format("[%s] %s（%d 民力）：%s", t.key, t.name, t.cost, t.desc), 140, y, 16, G.C.dim, "left", 700)
    y = y + h + 2
  end
  G.text("民力来源：迎进城的百姓（每人 2 点）和堡内屯田（每 12 秒 1 点）。", 120, y + 8, 16, G.C.dim, "left", 720)
  local mx, my = self.app.mouse()
  G.button(self.back, G.inRect(mx, my, self.back))
end

function Scene:mousepressed(x, y, b)
  if b == 1 and G.inRect(x, y, self.back) then A.play("click"); self.app.go("title") end
end

function Scene:keypressed(k)
  if k == "escape" or k == "return" or k == "space" then self.app.go("title") end
end

return Scene
