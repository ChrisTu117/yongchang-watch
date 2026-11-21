-- SPDX-License-Identifier: AGPL-3.0-only
-- 守城单位和来犯者的数值。数值由自动平衡测试（tests/test_balance.lua）约束。
local D = {}

-- 敌台上可安排的守城单位。cost 为民力。light 是自带灯笼的照明半径。
D.towers = {
  archer = { name = "弓手", key = "1", cost = 3, range = 120, dmg = 1, rate = 1.1, light = 46,
             speed = 420, desc = "射程中等，出手快。只能射中被照亮的敌人。" },
  gunner = { name = "鸟铳", key = "2", cost = 6, range = 165, dmg = 3, rate = 0.45, light = 46,
             speed = 700, desc = "射程远，威力大，装填慢。" },
  beacon = { name = "烽火", key = "3", cost = 2, range = 0, dmg = 0, rate = 0, light = 115,
             desc = "不攻击。点起烽火，长久照亮周围一大片。" },
}
D.towerOrder = { "archer", "gunner", "beacon" }
D.maxLevel = 3
-- 升级花费 = 基础花费 × 当前等级；每级伤害 ×1.5、射程 +15、照明 +10
function D.upgradeCost(kind, level) return D.towers[kind].cost * level end

-- 来犯者。gateDps：每秒砸城门的伤害；harm：冲进堡内扣的“堡安”。
D.enemies = {
  raider = { name = "寇兵", hp = 3, speed = 26, gateDps = 2, harm = 10, r = 7 },
  runner = { name = "轻寇", hp = 2, speed = 42, gateDps = 1, harm = 8,  r = 6 },
  brute  = { name = "重甲", hp = 9, speed = 17, gateDps = 4, harm = 15, r = 9 },
}

D.refugee = { speed = 30, patience = 14, reward = 2 }
D.gateHp = 24
D.wengchengBonus = 1.6   -- 东门有瓮城（两道门），更耐砸
D.repairCost = 4        -- 修复被攻破的城门
D.repairTo = 0.5        -- 修好后恢复到最大耐久的一半
D.anning = 100           -- 堡内安宁值，归零则失守
D.farmEvery = 12         -- 屯田：每隔多少秒民力 +1（堡内百余亩农田，战时自给）
D.boatSpeed = 60
D.beam = { len = 430, half = math.rad(16) }   -- 望楼光束
D.lantern = { radius = 170, duration = 7, cooldown = 22 }  -- 孔明灯
D.gateLight = 40
D.scatterDist = 13       -- 来犯者靠近百姓到这个距离，百姓就被冲散

return D
