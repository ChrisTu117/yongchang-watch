-- SPDX-License-Identifier: AGPL-3.0-only
local World = require("src.sim.world")
local Bot = require("src.sim.bot")
local L = require("src.data.levels")
local D = require("src.data.units")
local MAP = require("src.data.map")

-- 一个没有波次的空白夜晚，方便单独摆弄规则
local function blank(extra)
  local lv = { id = 99, title = "测试", duration = 60, minli = 20, waves = {} }
  for k, v in pairs(extra or {}) do lv[k] = v end
  return World.new(lv, { seed = 5 })
end

local function run(w, secs, fn)
  local steps = math.floor(secs * 30 + 0.5)
  for _ = 1, steps do
    if fn then fn(w) end
    w:update(1 / 30)
  end
end

T.case("地图：12 座敌台、4 座城门、4 座水门（与资料一致）", function()
  T.eq(#MAP.slots, 12)
  T.eq(#MAP.gates, 4)
  T.eq(#MAP.watergates, 4)
  local hasWeng = false
  for _, g in ipairs(MAP.gates) do if g.id == "E" and g.wengcheng then hasWeng = true end end
  T.ok(hasWeng, "东门有瓮城")
end)

T.case("每条路线都通向存在的城门，船路有出发点", function()
  local ids = {}
  for _, g in ipairs(MAP.gates) do ids[g.id] = g end
  for name, p in pairs(MAP.paths) do
    T.ok(ids[p.gate] ~= nil, name .. " 的城门存在")
    local last = p.pts[#p.pts]
    T.eq(last[1], ids[p.gate].fx, name .. " 终点 x 在门前")
    T.eq(last[2], ids[p.gate].fy, name .. " 终点 y 在门前")
  end
  for i = 1, L.count do
    for _, wv in ipairs(L[i].waves) do
      T.ok(MAP.paths[wv.path] ~= nil, "第" .. i .. "夜路线 " .. wv.path)
      if wv.boat then T.ok(MAP.boatFrom[wv.path] ~= nil, "船路 " .. wv.path) end
      T.ok(wv.kind == "refugee" or D.enemies[wv.kind] ~= nil, "种类 " .. wv.kind)
    end
  end
end)

T.case("安排守城单位要花民力，民力不够会提示", function()
  local w = blank({ minli = 4 })
  T.ok(w:build(5, "archer"))
  T.eq(w.minli, 4 - D.towers.archer.cost)
  local ok, why = w:build(6, "gunner")
  T.ok(not ok); T.eq(why, "nomoney")
  local sawNoMoney = false
  for _, e in ipairs(w:drainEvents()) do if e.type == "nomoney" then sawNoMoney = true end end
  T.ok(sawNoMoney, "发出民力不足事件")
end)

T.case("再点已有单位就是升级，最多三级", function()
  local w = blank({ minli = 100 })
  w:build(1, "archer")
  T.ok(w:build(1, "archer"))          -- 升到 2 级
  T.eq(w.slots[1].tower.level, 2)
  T.ok(w:upgrade(1))                  -- 3 级
  local ok, why = w:upgrade(1)
  T.ok(not ok); T.eq(why, "max")
  local st = w:towerStats(w.slots[1].tower)
  T.near(st.dmg, D.towers.archer.dmg * 2.25)
  T.eq(st.range, D.towers.archer.range + 30)
end)

T.case("城门开关", function()
  local w = blank()
  local g = w.gateById.W
  T.ok(not g.open)
  w:clickGate("W"); T.ok(g.open)
  w:clickGate("W"); T.ok(not g.open)
end)

T.case("视野：堡内总是亮；光束照到的地方亮；黑暗里看不见", function()
  local w = blank()
  T.ok(w:isLit(430, 270), "堡内")
  w:aim(900, 270)                     -- 照向正东
  T.ok(w:isLit(800, 270), "光束内")
  T.ok(not w:isLit(800, 60), "光束外")
  T.ok(not w:isLit(100, 270), "背后")
  w:build(4, "beacon")                -- 东北角烽火
  T.ok(w:isLit(640, 60), "烽火照亮")
  T.ok(w:launchLantern(100, 500))
  T.ok(w:isLit(120, 480), "孔明灯")
  T.ok(not w:launchLantern(100, 100), "孔明灯冷却中")
end)

T.case("塔只打被照亮的敌人", function()
  local w = blank({ minli = 50 })
  w:build(5, "archer")                -- 东墙敌台 (560,175)，射程 120，灯笼 62
  w.slots[5].tower.cd = 0
  local e = w:spawnUnit("raider", "north_E")
  e.x, e.y, e.remain = 650, 140, 100  -- 射程内、灯笼外、离城门火把也远
  w:aim(100, 270)                     -- 光束背对敌人
  e.lit = w:isLit(e.x, e.y)
  T.ok(not e.lit, "黑暗中")
  w:updateTowers(0.1)
  T.eq(#w.shots, 0, "看不见就不放箭")
  w:aim(650, 140)                     -- 望向敌人
  e.lit = w:isLit(e.x, e.y)
  T.ok(e.lit, "被光束照亮")
  w:updateTowers(0.1)
  T.eq(#w.shots, 1, "照亮后放箭")
  for _ = 1, 30 do w:updateShots(1 / 30) end
  T.ok(e.hp < e.maxhp, "射中")
end)

T.case("敌人砸关着的城门，城门会被攻破，攻破后可以修", function()
  local w = blank({ minli = 10 })
  local g = w.gateById.W
  local e = w:spawnUnit("brute", "hill_W")
  e.d = World.PATHLEN.hill_W.total
  run(w, 0.5)
  T.ok(g.hp < g.maxhp, "城门掉耐久")
  T.eq(w.anning, D.anning, "门没破前堡安不变")
  run(w, 10)
  T.ok(g.broken, "城门被攻破")
  T.ok(w.anning < D.anning, "攻破后敌人进堡")
  T.ok(w:clickGate("W"), "点被攻破的城门 = 修复")
  T.ok(not g.broken and not g.open)
  T.near(g.hp, g.maxhp * D.repairTo)
  T.eq(w.minli, 10 - D.repairCost)
end)

T.case("东门有瓮城，更耐砸", function()
  local w = blank()
  T.ok(w.gateById.E.maxhp > w.gateById.W.maxhp)
end)

T.case("城门开着时敌人直接冲进堡，扣堡安", function()
  local w = blank()
  w:clickGate("E")
  local e = w:spawnUnit("raider", "mid_E")
  e.d = World.PATHLEN.mid_E.total - 1
  run(w, 0.5)
  T.eq(w.anning, D.anning - D.enemies.raider.harm)
  T.eq(#w.enemies, 0)
end)

T.case("开门迎百姓：进堡得民力；不开门，等久了会离开", function()
  local w = blank({ minli = 0 })
  local r = w:spawnUnit("refugee", "ref_W")
  r.d = World.PATHLEN.ref_W.total
  run(w, 1)
  T.eq(w.saved, 0, "门关着进不来")
  w:clickGate("W")
  run(w, 0.2)
  T.eq(w.saved, 1)
  T.eq(w.minli, D.refugee.reward)
  local w2 = blank()
  local r2 = w2:spawnUnit("refugee", "ref_W")
  r2.d = World.PATHLEN.ref_W.total
  run(w2, D.refugee.patience + 1)
  T.eq(w2.lost, 1, "等不到开门就离开")
end)

T.case("来犯者冲散百姓", function()
  local w = blank()
  local r = w:spawnUnit("refugee", "ref_W")
  local e = w:spawnUnit("raider", "hill_W")
  e.x, e.y = r.x, r.y
  w:updateRefugees(0.01)
  T.eq(w.lost, 1)
end)

T.case("屯田：每隔一段时间民力 +1", function()
  local w = blank({ minli = 0 })
  run(w, D.farmEvery + 0.1)
  T.eq(w.minli, 1)
end)

T.case("天亮即守住；堡安归零即失守", function()
  local w = blank({ duration = 3 })
  run(w, 3.2)
  T.eq(w.state, "won")
  T.ok(w:stars() >= 1)
  local w2 = blank()
  w2.anning = 5
  w2:clickGate("E")
  local e = w2:spawnUnit("raider", "mid_E")
  e.d = World.PATHLEN.mid_E.total - 1
  run(w2, 0.5)
  T.eq(w2.state, "lost")
  T.eq(w2:stars(), 0)
end)

T.case("第一夜教学：四步依次完成，之后才开始计时", function()
  local w = World.new(L[1], {})
  local bot = Bot.new("smart")
  T.eq(w.tut.step, World.TUT.LOOK)
  local seen = {}
  local steps = 0
  while w:tutorialActive() and steps < 30 * 120 do
    bot:act(w, 1 / 30); w:update(1 / 30); steps = steps + 1
    for _, ev in ipairs(w:drainEvents()) do if ev.type == "tut" then seen[#seen + 1] = ev.step end end
    if w:tutorialActive() then T.eq(w.t, 0, "教学时夜晚时钟不走") end
  end
  T.eq(table.concat(seen, ","), "2,3,4,5", "四步顺序")
  T.ok(w.saved >= 1, "教学中救下百姓")
end)

T.case("同样的操作得到同样的结果（确定性）", function()
  local function play()
    local w = World.new(L[2], {})
    local bot = Bot.new("smart")
    while w.state == "playing" do bot:act(w, 1 / 30); w:update(1 / 30); w:drainEvents() end
    return string.format("%s %d %d %d %d", w.state, w.anning, w.saved, w.kills, w.minli)
  end
  T.eq(play(), play())
end)

T.case("民力只来自百姓和屯田：打退敌人不给民力", function()
  local w = blank({ minli = 0 })
  w:build(5, "archer")
  local e = w:spawnUnit("raider", "north_E")
  e.hp = 0.5
  e.x, e.y, e.remain = 600, 180, 100
  w:aim(600, 180)
  e.lit = true
  w.slots[5].tower = { kind = "archer", level = 1, cd = 0 }
  w:updateTowers(0.1)
  for _ = 1, 30 do w:updateShots(1 / 30) end
  T.eq(w.kills, 1)
  T.eq(w.minli, 0)
end)
