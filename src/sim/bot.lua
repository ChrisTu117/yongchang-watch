-- SPDX-License-Identifier: AGPL-3.0-only
-- 自动玩家：只用于自动测试和平衡检查，不出现在正常游戏里。
-- 它只能做真人能做的操作：瞄准光束、点敌台、开关城门、放孔明灯。
local U = require("src.util")
local MAP = require("src.data.map")
local D = require("src.data.units")

local Bot = {}
Bot.__index = Bot

-- style: "smart"（正常策略）或 "idle"（什么都不做，用来证明不操作必输）
function Bot.new(style)
  return setmetatable({ style = style or "smart", sweep = 0, thinkTimer = 0 }, Bot)
end

-- 建造顺序：先东面（海上来敌最多），再南北，最后西面。
local PLAN = {
  { 5, "archer" }, { 6, "beacon" }, { 4, "archer" }, { 7, "archer" },
  { 5, "upgrade" }, { 3, "gunner" }, { 8, "gunner" }, { 12, "archer" }, { 11, "archer" },
  { 2, "beacon" }, { 9, "beacon" }, { 6, "upgrade" }, { 4, "upgrade" }, { 7, "upgrade" },
  { 1, "archer" }, { 10, "archer" }, { 3, "upgrade" }, { 8, "upgrade" }, { 12, "upgrade" },
  { 11, "upgrade" }, { 5, "upgrade" },
}

function Bot:act(w, dt)
  if self.style == "idle" or w.state ~= "playing" then return end
  self.thinkTimer = self.thinkTimer - dt

  -- 教学：按提示做
  if w:tutorialActive() then
    local step = w.tut.step
    if step == w.TUT.LOOK then w:aim(900, 270) end
  end

  -- 光束：照向离城门最近、还没被照亮的敌人；没有就照最近的船；都没有就来回扫
  local target, best = nil, math.huge
  for _, e in ipairs(w.enemies) do
    -- 已经被别的灯照亮的不用管；优先照离城门最近的暗处敌人
    local litByOthers = e.lit and not w:inBeam(e.x, e.y)
    local r = e.remain or 0
    if not litByOthers and r < best then target, best = e, r end
  end
  if not target then
    for _, b in ipairs(w.boats) do
      local d = U.dist(b.x, b.y, b.tx, b.ty)
      if d < best then target, best = b, d end
    end
  end
  if target and not (w:tutorialActive() and w.tut.step == w.TUT.LOOK) then
    w:aim(target.x, target.y)
  elseif not target and not w:tutorialActive() then
    self.sweep = self.sweep + dt * 0.8
    w:aim(MAP.center.x + math.cos(self.sweep) * 300, MAP.center.y + math.sin(self.sweep) * 200)
  end

  -- 孔明灯：有两个以上敌人在黑暗里时放到他们中间
  if w.lanternCd <= 0 then
    local sx, sy, n = 0, 0, 0
    for _, e in ipairs(w.enemies) do
      if not e.lit then sx, sy, n = sx + e.x, sy + e.y, n + 1 end
    end
    if n >= 3 then w:launchLantern(sx / n, sy / n) end
  end

  -- 城门：有百姓在门前、附近没有敌人就开；否则关
  for _, g in ipairs(w.gates) do
    if g.broken and w.minli >= D.repairCost then w:repairGate(g.id) end
    local refugeeNear, enemyNear = false, false
    for _, r in ipairs(w.refugees) do
      if MAP.paths[r.path].gate == g.id and U.dist(r.x, r.y, g.fx, g.fy) < 60 then refugeeNear = true end
    end
    for _, e in ipairs(w.enemies) do
      if MAP.paths[e.path].gate == g.id and (e.remain or 999) < 110 then enemyNear = true end
    end
    w:setGate(g.id, refugeeNear and not enemyNear)
  end

  -- 建造：每 0.5 秒想一次，按计划顺序花钱，一次一项
  if self.thinkTimer <= 0 then
    self.thinkTimer = 0.5
    self.planIdx = self.planIdx or 1
    local item = PLAN[self.planIdx]
    if item then
      local slot = w.slots[item[1]]
      if item[2] == "upgrade" then
        if not slot.tower or slot.tower.level >= D.maxLevel then
          self.planIdx = self.planIdx + 1
        elseif w.minli >= D.upgradeCost(slot.tower.kind, slot.tower.level) then
          w:upgrade(item[1]); self.planIdx = self.planIdx + 1
        end
      elseif slot.tower then
        self.planIdx = self.planIdx + 1
      elseif w.minli >= D.towers[item[2]].cost then
        w:build(item[1], item[2]); self.planIdx = self.planIdx + 1
      end
    end
  end
end

return Bot
