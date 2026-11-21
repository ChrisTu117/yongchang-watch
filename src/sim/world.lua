-- SPDX-License-Identifier: AGPL-3.0-only
-- 一个夜晚的全部规则。这里不调用任何 love.* 接口，可以在纯 Lua（LuaJIT / Lua 5.5）里单独测试。
local U = require("src.util")
local MAP = require("src.data.map")
local D = require("src.data.units")

local World = {}
World.__index = World

-- 预先算好每条路线的累计长度
local PATHLEN = {}
for name, p in pairs(MAP.paths) do
  local cum, total = { 0 }, 0
  for i = 2, #p.pts do
    total = total + U.dist(p.pts[i - 1][1], p.pts[i - 1][2], p.pts[i][1], p.pts[i][2])
    cum[i] = total
  end
  PATHLEN[name] = { cum = cum, total = total }
end

local function pointOnPath(name, d)
  local p, L = MAP.paths[name].pts, PATHLEN[name]
  if d <= 0 then return p[1][1], p[1][2] end
  if d >= L.total then return p[#p][1], p[#p][2] end
  for i = 2, #p do
    if L.cum[i] >= d then
      local seg = L.cum[i] - L.cum[i - 1]
      local t = seg > 0 and (d - L.cum[i - 1]) / seg or 0
      return U.lerp(p[i - 1][1], p[i][1], t), U.lerp(p[i - 1][2], p[i][2], t)
    end
  end
  return p[#p][1], p[#p][2]
end
World.pointOnPath = pointOnPath
World.PATHLEN = PATHLEN

function World.new(level, opts)
  opts = opts or {}
  local w = setmetatable({}, World)
  w.level = level
  w.rng = U.rng(opts.seed or (level.id * 7919))
  w.t = 0                 -- 夜晚时钟：到 duration 天亮。教学步骤进行时暂停
  w.real = 0
  w.duration = level.duration
  w.state = "playing"
  w.minli = level.minli
  w.anning = D.anning
  w.saved, w.lost, w.refugeesSpawned = 0, 0, 0
  w.kills, w.entered, w.breaches = 0, 0, 0
  w.farmTimer = 0
  w.gates, w.gateById = {}, {}
  for i, g in ipairs(MAP.gates) do
    local maxhp = g.wengcheng and D.gateHp * D.wengchengBonus or D.gateHp
    local gate = { id = g.id, name = g.name, x = g.x, y = g.y, fx = g.fx, fy = g.fy,
                   hp = maxhp, maxhp = maxhp, open = false, broken = false, flash = 0,
                   wengcheng = g.wengcheng }
    w.gates[i] = gate
    w.gateById[g.id] = gate
  end
  w.slots = {}
  for i, s in ipairs(MAP.slots) do w.slots[i] = { i = i, x = s.x, y = s.y, tower = nil } end
  w.enemies, w.refugees, w.shots, w.boats, w.spawners = {}, {}, {}, {}, {}
  w.events = {}
  w.beam = { x = MAP.center.x, y = MAP.center.y, angle = math.pi }  -- 开局朝西（背对大海）
  w.lantern, w.lanternCd = nil, 0
  w.waves = {}
  for i, wv in ipairs(level.waves) do w.waves[i] = wv end
  table.sort(w.waves, function(a, b) return a.t < b.t end)
  w.waveIdx = 1
  w.nextId = 1
  if level.tutorial and not opts.skipTutorial then
    w.tut = { step = 1, look = 0, started = {} }
  end
  return w
end

function World:emit(ev) self.events[#self.events + 1] = ev end

function World:drainEvents()
  local e = self.events
  self.events = {}
  return e
end

function World:id()
  self.nextId = self.nextId + 1
  return self.nextId
end

----------------------------------------------------------------- 玩家操作
function World:aim(x, y)
  self.beam.angle = U.atan2(y - self.beam.y, x - self.beam.x)
end

function World:towerStats(t)
  local b = D.towers[t.kind]
  local lv = t.level - 1
  return {
    range = b.range > 0 and (b.range + 15 * lv) or 0,
    dmg = b.dmg * (1.5 ^ lv),
    rate = b.rate,
    light = b.light + 10 * lv,
    speed = b.speed,
  }
end

-- 在敌台上安排守城单位；已有单位时升级。返回 true/false 和原因。
function World:build(slotIndex, kind)
  local s = self.slots[slotIndex]
  if not s or self.state ~= "playing" then return false, "invalid" end
  if s.tower then return self:upgrade(slotIndex) end
  local def = D.towers[kind]
  if not def then return false, "invalid" end
  if self.minli < def.cost then
    self:emit({ type = "nomoney", x = s.x, y = s.y, need = def.cost })
    return false, "nomoney"
  end
  self.minli = self.minli - def.cost
  s.tower = { kind = kind, level = 1, cd = 0.3 }
  self:emit({ type = "build", x = s.x, y = s.y, kind = kind })
  return true
end

function World:upgrade(slotIndex)
  local s = self.slots[slotIndex]
  if not s or not s.tower then return false, "invalid" end
  local t = s.tower
  if t.level >= D.maxLevel then
    self:emit({ type = "maxlevel", x = s.x, y = s.y })
    return false, "max"
  end
  local cost = D.upgradeCost(t.kind, t.level)
  if self.minli < cost then
    self:emit({ type = "nomoney", x = s.x, y = s.y, need = cost })
    return false, "nomoney"
  end
  self.minli = self.minli - cost
  t.level = t.level + 1
  self:emit({ type = "upgrade", x = s.x, y = s.y, kind = t.kind, level = t.level })
  return true
end

-- 点城门：完好时开/关；被攻破时花民力修复（修好后是关着的）
function World:clickGate(id)
  local g = self.gateById[id]
  if not g then return false end
  if g.broken then return self:repairGate(id) end
  return self:toggleGate(id)
end

function World:repairGate(id)
  local g = self.gateById[id]
  if not g or not g.broken or self.state ~= "playing" then return false end
  if self.minli < D.repairCost then
    self:emit({ type = "nomoney", x = g.x, y = g.y, need = D.repairCost })
    return false
  end
  self.minli = self.minli - D.repairCost
  g.broken, g.open = false, false
  g.hp = g.maxhp * D.repairTo
  self:emit({ type = "repair", x = g.x, y = g.y, gate = id })
  return true
end

function World:toggleGate(id)
  local g = self.gateById[id]
  if not g or g.broken or self.state ~= "playing" then return false end
  g.open = not g.open
  self:emit({ type = g.open and "gateopen" or "gateclose", x = g.x, y = g.y, gate = id })
  return true
end

function World:setGate(id, open)
  local g = self.gateById[id]
  if g and not g.broken and g.open ~= open then self:toggleGate(id) end
end

function World:launchLantern(x, y)
  if self.lanternCd > 0 or self.state ~= "playing" then return false end
  self.lantern = { x = x, y = y, t = D.lantern.duration }
  self.lanternCd = D.lantern.cooldown
  self:emit({ type = "lantern", x = x, y = y })
  return true
end

----------------------------------------------------------------- 视野（望）
function World:inBeam(x, y)
  local b = self.beam
  local d2 = U.dist2(b.x, b.y, x, y)
  if d2 > D.beam.len * D.beam.len then return false end
  if d2 < 40 * 40 then return true end
  local a = U.atan2(y - b.y, x - b.x)
  return math.abs(U.angdiff(a, b.angle)) <= D.beam.half
end

function World:isLit(x, y)
  local f = MAP.fort
  if x >= f.x1 and x <= f.x2 and y >= f.y1 and y <= f.y2 then return true end
  if self:inBeam(x, y) then return true end
  for _, s in ipairs(self.slots) do
    if s.tower then
      local r = self:towerStats(s.tower).light
      if U.dist2(s.x, s.y, x, y) <= r * r then return true end
    end
  end
  for _, g in ipairs(self.gates) do
    if U.dist2(g.x, g.y, x, y) <= D.gateLight * D.gateLight then return true end
  end
  local l = self.lantern
  if l and U.dist2(l.x, l.y, x, y) <= D.lantern.radius * D.lantern.radius then return true end
  return false
end

----------------------------------------------------------------- 生成
function World:spawnUnit(kind, path, tag)
  local u = {
    id = self:id(), kind = kind, path = path, d = 0, tag = tag,
    ox = self.rng:range(-5, 5), oy = self.rng:range(-5, 5),
  }
  if kind == "refugee" then
    u.wait = 0
    u.x, u.y = pointOnPath(path, 0)
    self.refugees[#self.refugees + 1] = u
    self.refugeesSpawned = self.refugeesSpawned + 1
  else
    local def = D.enemies[kind]
    u.hp, u.maxhp = def.hp, def.hp
    u.x, u.y = pointOnPath(path, 0)
    self.enemies[#self.enemies + 1] = u
  end
  return u
end

function World:startGroup(wave, tag)
  if wave.boat then
    local from = MAP.boatFrom[wave.path]
    local to = MAP.paths[wave.path].pts[1]
    self.boats[#self.boats + 1] = {
      id = self:id(), x = from[1], y = from[2], tx = to[1], ty = to[2],
      wave = wave, tag = tag, lit = false,
    }
  else
    self.spawners[#self.spawners + 1] = { wave = wave, left = wave.n, timer = 0, tag = tag }
  end
end

----------------------------------------------------------------- 教学
local TUT_LOOK, TUT_BUILD, TUT_OPEN, TUT_CLOSE, TUT_DONE = 1, 2, 3, 4, 5
World.TUT = { LOOK = TUT_LOOK, BUILD = TUT_BUILD, OPEN = TUT_OPEN, CLOSE = TUT_CLOSE, DONE = TUT_DONE }

function World:countTagged(list, tag)
  local n = 0
  for _, u in ipairs(list) do if u.tag == tag then n = n + 1 end end
  return n
end

function World:tutorialActive() return self.tut ~= nil and self.tut.step < TUT_DONE end

function World:advanceTutorial(dt)
  local tut = self.tut
  if tut.step == TUT_LOOK then
    if math.abs(U.angdiff(self.beam.angle, 0)) < math.rad(35) then tut.look = tut.look + dt end
    if tut.look >= 0.8 then tut.step = TUT_BUILD; self:emit({ type = "tut", step = tut.step }) end
  elseif tut.step == TUT_BUILD then
    for _, s in ipairs(self.slots) do
      if s.tower then tut.step = TUT_OPEN; self:emit({ type = "tut", step = tut.step }); break end
    end
  elseif tut.step == TUT_OPEN then
    if not tut.started[TUT_OPEN] then
      tut.started[TUT_OPEN] = true
      self:startGroup({ kind = "refugee", path = "ref_W", n = 3, gap = 1.2 }, "tut")
    end
    if self:countTagged(self.refugees, "tut") == 0 and #self.spawners == 0 then
      tut.step = TUT_CLOSE; self:emit({ type = "tut", step = tut.step })
    end
  elseif tut.step == TUT_CLOSE then
    if not tut.started[TUT_CLOSE] then
      tut.started[TUT_CLOSE] = true
      self:startGroup({ kind = "raider", path = "mid_E", n = 2, gap = 1.6, boat = true }, "tut")
    end
    if self:countTagged(self.enemies, "tut") == 0 and #self.spawners == 0 and #self.boats == 0 then
      tut.step = TUT_DONE; self:emit({ type = "tut", step = tut.step })
    end
  end
end

----------------------------------------------------------------- 更新
function World:update(dt)
  if self.state ~= "playing" then return end
  if dt > 0.1 then dt = 0.1 end
  self.real = self.real + dt

  local clockRuns = true
  if self.tut and self.tut.step < TUT_DONE then
    self:advanceTutorial(dt)
    clockRuns = self.tut.step >= TUT_DONE
  end

  if clockRuns then
    self.t = self.t + dt
    -- 波次
    while self.waveIdx <= #self.waves and self.waves[self.waveIdx].t <= self.t do
      self:startGroup(self.waves[self.waveIdx], nil)
      self.waveIdx = self.waveIdx + 1
    end
    -- 屯田
    self.farmTimer = self.farmTimer + dt
    if self.farmTimer >= D.farmEvery then
      self.farmTimer = self.farmTimer - D.farmEvery
      self.minli = self.minli + 1
      self:emit({ type = "farm" })
    end
  end

  -- 孔明灯
  if self.lanternCd > 0 then self.lanternCd = math.max(0, self.lanternCd - dt) end
  if self.lantern then
    self.lantern.t = self.lantern.t - dt
    if self.lantern.t <= 0 then self.lantern = nil end
  end

  self:updateBoats(dt)
  self:updateSpawners(dt)
  self:updateRefugees(dt)
  self:updateEnemies(dt)
  self:updateTowers(dt)
  self:updateShots(dt)
  for _, g in ipairs(self.gates) do if g.flash > 0 then g.flash = math.max(0, g.flash - dt) end end

  if self.anning <= 0 then
    self.anning = 0
    self.state = "lost"
    self:emit({ type = "lost" })
  elseif self.t >= self.duration then
    self.state = "won"
    self:emit({ type = "won" })
  end
end

function World:updateBoats(dt)
  local keep = {}
  for _, b in ipairs(self.boats) do
    local d = U.dist(b.x, b.y, b.tx, b.ty)
    local step = D.boatSpeed * dt
    if d <= step then
      self.spawners[#self.spawners + 1] = { wave = b.wave, left = b.wave.n, timer = 0, tag = b.tag }
      self:emit({ type = "land", x = b.tx, y = b.ty })
    else
      b.x = b.x + (b.tx - b.x) / d * step
      b.y = b.y + (b.ty - b.y) / d * step
      b.lit = self:isLit(b.x, b.y)
      keep[#keep + 1] = b
    end
  end
  self.boats = keep
end

function World:updateSpawners(dt)
  local keep = {}
  for _, sp in ipairs(self.spawners) do
    sp.timer = sp.timer - dt
    while sp.left > 0 and sp.timer <= 0 do
      self:spawnUnit(sp.wave.kind, sp.wave.path, sp.tag)
      sp.left = sp.left - 1
      sp.timer = sp.timer + (sp.wave.gap or 1)
    end
    if sp.left > 0 then keep[#keep + 1] = sp end
  end
  self.spawners = keep
end

function World:updateRefugees(dt)
  local keep = {}
  for _, r in ipairs(self.refugees) do
    local total = PATHLEN[r.path].total
    local gate = self.gateById[MAP.paths[r.path].gate]
    local done = false
    if r.d < total then
      r.d = math.min(total, r.d + D.refugee.speed * dt)
    end
    r.x, r.y = pointOnPath(r.path, r.d)
    if r.d >= total then
      if gate.open or gate.broken then
        self.saved = self.saved + 1
        self.minli = self.minli + D.refugee.reward
        self:emit({ type = "saved", x = gate.x, y = gate.y, amount = D.refugee.reward })
        done = true
      else
        r.wait = r.wait + dt
        if r.tag ~= "tut" and r.wait > D.refugee.patience then
          self.lost = self.lost + 1
          self:emit({ type = "leave", x = r.x, y = r.y })
          done = true
        end
      end
    end
    if not done then
      for _, e in ipairs(self.enemies) do
        if U.dist2(e.x, e.y, r.x, r.y) <= D.scatterDist * D.scatterDist then
          self.lost = self.lost + 1
          self:emit({ type = "scatter", x = r.x, y = r.y })
          done = true
          break
        end
      end
    end
    if not done then keep[#keep + 1] = r end
  end
  self.refugees = keep
end

function World:updateEnemies(dt)
  local keep = {}
  for _, e in ipairs(self.enemies) do
    local def = D.enemies[e.kind]
    local total = PATHLEN[e.path].total
    local gate = self.gateById[MAP.paths[e.path].gate]
    local gone = false
    if e.d < total then
      e.d = math.min(total, e.d + def.speed * dt)
      e.x, e.y = pointOnPath(e.path, e.d)
    end
    if e.d >= total then
      if gate.open or gate.broken then
        self.anning = self.anning - def.harm
        self.entered = self.entered + 1
        self:emit({ type = "enter", x = gate.x, y = gate.y, gate = gate.id, harm = def.harm })
        gone = true
      else
        gate.hp = gate.hp - def.gateDps * dt
        gate.flash = 0.15
        e.bash = (e.bash or 0) + dt
        if e.bash >= 0.6 then
          e.bash = 0
          self:emit({ type = "gatehit", x = gate.x, y = gate.y, gate = gate.id })
        end
        if gate.hp <= 0 then
          gate.hp = 0
          gate.broken = true
          gate.open = true
          self.breaches = self.breaches + 1
          self:emit({ type = "breach", x = gate.x, y = gate.y, gate = gate.id })
        end
      end
    end
    e.remain = total - e.d
    e.lit = self:isLit(e.x, e.y)
    if not gone then keep[#keep + 1] = e end
  end
  self.enemies = keep
end

function World:findEnemy(id)
  for _, e in ipairs(self.enemies) do if e.id == id then return e end end
  return nil
end

function World:updateTowers(dt)
  for _, s in ipairs(self.slots) do
    local t = s.tower
    if t then
      local st = self:towerStats(t)
      t.cd = t.cd - dt
      if st.range > 0 and t.cd <= 0 then
        local best, bestRemain = nil, math.huge
        for _, e in ipairs(self.enemies) do
          if e.lit and U.dist2(s.x, s.y, e.x, e.y) <= st.range * st.range then
            local remain = e.remain or 0
            if remain < bestRemain then best, bestRemain = e, remain end
          end
        end
        if best then
          t.cd = 1 / st.rate
          t.aim = U.atan2(best.y - s.y, best.x - s.x)
          self.shots[#self.shots + 1] = {
            x = s.x, y = s.y, target = best.id, dmg = st.dmg, speed = st.speed, kind = t.kind,
          }
          self:emit({ type = "shoot", x = s.x, y = s.y, kind = t.kind })
        else
          t.cd = 0
        end
      end
    end
  end
end

function World:updateShots(dt)
  local keep = {}
  for _, sh in ipairs(self.shots) do
    local e = self:findEnemy(sh.target)
    if e then
      local d = U.dist(sh.x, sh.y, e.x, e.y)
      local step = sh.speed * dt
      if d <= step + 4 then
        e.hp = e.hp - sh.dmg
        self:emit({ type = "hit", x = e.x, y = e.y })
        if e.hp <= 0 then
          self.kills = self.kills + 1
          self:emit({ type = "kill", x = e.x, y = e.y, kind = e.kind })
          for i, x in ipairs(self.enemies) do
            if x == e then table.remove(self.enemies, i); break end
          end
        end
      else
        sh.x = sh.x + (e.x - sh.x) / d * step
        sh.y = sh.y + (e.y - sh.y) / d * step
        keep[#keep + 1] = sh
      end
    end
  end
  self.shots = keep
end

----------------------------------------------------------------- 结算
function World:stars()
  if self.state ~= "won" then return 0 end
  local ratio = self.refugeesSpawned > 0 and self.saved / self.refugeesSpawned or 1
  if self.anning >= 80 and ratio >= 0.7 then return 3 end
  if self.anning >= 50 then return 2 end
  return 1
end

function World:progress() return U.clamp(self.t / self.duration, 0, 1) end

return World
