-- SPDX-License-Identifier: AGPL-3.0-only
-- 平衡检查：会玩能赢、不玩必输、“望”和“迎百姓”都确实有用。
local World = require("src.sim.world")
local Bot = require("src.sim.bot")
local L = require("src.data.levels")

local function play(lv, style, tweak)
  local w = World.new(L[lv], { skipTutorial = style ~= "smart" })
  local b = Bot.new(style == "idle" and "idle" or "smart")
  local steps = 0
  while w.state == "playing" and steps < 30 * 400 do
    b:act(w, 1 / 30)
    if tweak then tweak(w) end
    w:update(1 / 30)
    w:drainEvents()
    steps = steps + 1
  end
  return w
end

local noBeam = function(w) w:aim(w.beam.x - 100, w.beam.y) ; w.lanternCd = 99 end   -- 光束永远朝西、不放孔明灯
local noGate = function(w) for _, g in ipairs(w.gates) do if g.open and not g.broken then g.open = false end end end

T.case("正常策略三夜都能守住，且留有余量", function()
  for lv = 1, L.count do
    local w = play(lv, "smart")
    T.eq(w.state, "won", "第" .. lv .. "夜")
    T.ok(w.anning >= 40, "第" .. lv .. "夜堡安余量 " .. w.anning)
  end
end)

T.case("什么都不做，三夜都会失守", function()
  for lv = 1, L.count do
    local w = play(lv, "idle")
    T.eq(w.state, "lost", "第" .. lv .. "夜")
  end
end)

T.case("不用光束“望”，明显守得更差", function()
  for lv = 2, L.count do
    local good = play(lv, "smart")
    local blind = play(lv, "blind", noBeam)
    local goodScore = (good.state == "won" and 1000 or 0) + good.anning
    local blindScore = (blind.state == "won" and 1000 or 0) + blind.anning
    T.ok(blindScore < goodScore, "第" .. lv .. "夜：望 " .. goodScore .. " vs 不望 " .. blindScore)
  end
end)

T.case("不开门迎百姓，救不到人、民力更少", function()
  for lv = 1, L.count do
    local good = play(lv, "smart")
    local closed = play(lv, "closed", noGate)
    T.eq(closed.saved, 0, "第" .. lv .. "夜不开门")
    T.ok(good.saved > 0)
    local function levels(w)
      local n = 0
      for _, sl in ipairs(w.slots) do if sl.tower then n = n + sl.tower.level end end
      return n
    end
    T.ok(levels(closed) < levels(good), "第" .. lv .. "夜守城单位总等级 " .. levels(closed) .. " < " .. levels(good))
  end
end)
