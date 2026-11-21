-- SPDX-License-Identifier: AGPL-3.0-only
-- 笔画评判：玩家拖出的一条线是否像模板笔画（起点、终点、方向、整体形状）。纯 Lua，可单独测试。
local U = require("src.util")

local Stroke = {}
Stroke.N = 16          -- 重采样点数
Stroke.TOL = 0.10      -- 平均偏差容忍（田字格边长的 10%）
Stroke.END_TOL = 0.16  -- 起止点容忍

-- 返回 ok, info。info.reason 为 "short" / "start" / "end" / "shape" / nil
function Stroke.evaluate(template, drawn)
  if #drawn < 2 or U.polylen(drawn) < 0.04 then return false, { reason = "short" } end
  local a = template[1]
  local z = template[#template]
  local s = drawn[1]
  local e = drawn[#drawn]
  local dStart = U.dist(a[1], a[2], s[1], s[2])
  local dEnd = U.dist(z[1], z[2], e[1], e[2])
  -- 方向写反了：起点靠近模板终点、终点靠近模板起点
  if dStart > Stroke.END_TOL and U.dist(z[1], z[2], s[1], s[2]) < Stroke.END_TOL
     and U.dist(a[1], a[2], e[1], e[2]) < Stroke.END_TOL then
    return false, { reason = "reverse", dStart = dStart, dEnd = dEnd }
  end
  if dStart > Stroke.END_TOL then return false, { reason = "start", dStart = dStart } end
  if dEnd > Stroke.END_TOL then return false, { reason = "end", dEnd = dEnd } end
  local A = U.resample(template, Stroke.N)
  local B = U.resample(drawn, Stroke.N)
  local sum = 0
  for i = 1, Stroke.N do sum = sum + U.dist(A[i][1], A[i][2], B[i][1], B[i][2]) end
  local mean = sum / Stroke.N
  if mean > Stroke.TOL then return false, { reason = "shape", mean = mean } end
  return true, { mean = mean, score = U.clamp(1 - mean / Stroke.TOL, 0, 1) }
end

-- 一个字的描写进度
local Session = {}
Session.__index = Session

function Stroke.session(charDef)
  return setmetatable({ def = charDef, idx = 1, fails = 0, done = {}, scores = {} }, Session)
end

function Session:current() return self.def.strokes[self.idx] end
function Session:finished() return self.idx > #self.def.strokes end

-- 提交一笔。返回 ok, info
function Session:submit(drawn)
  local st = self:current()
  if not st then return false, { reason = "finished" } end
  local ok, info = Stroke.evaluate(st.pts, drawn)
  if ok then
    self.done[self.idx] = drawn
    self.scores[self.idx] = info.score
    self.idx = self.idx + 1
    self.fails = 0
  else
    self.fails = self.fails + 1
  end
  return ok, info
end

-- 连错三次后允许“请师傅带一笔”：自动补上这一笔（得分记 0）
function Session:assist()
  local st = self:current()
  if not st then return false end
  self.done[self.idx] = st.pts
  self.scores[self.idx] = 0
  self.idx = self.idx + 1
  self.fails = 0
  return true
end

function Session:score()
  local n, sum = #self.def.strokes, 0
  for i = 1, n do sum = sum + (self.scores[i] or 0) end
  return n > 0 and sum / n or 0
end

return Stroke
