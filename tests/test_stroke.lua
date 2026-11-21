-- SPDX-License-Identifier: AGPL-3.0-only
local Stroke = require("src.sim.stroke")
local S = require("src.data.strokes")
local U = require("src.util")

-- 独立参考：汉典的笔顺编号（tests/reference/bishun-zdic.txt）
local function loadRef()
  local ref = {}
  for line in io.lines("tests/reference/bishun-zdic.txt") do
    local ch, code = line:match("^([^#%s]+)%s+(%d+)$")
    if ch then ref[ch] = code end
  end
  return ref
end

local CODE = { ["横"] = "1", ["竖"] = "2", ["撇"] = "3", ["点"] = "4", ["捺"] = "4" }

T.case("四个字的笔顺与汉典一致", function()
  local ref = loadRef()
  for _, ch in ipairs(S.order) do
    local codes = {}
    for _, st in ipairs(S[ch].strokes) do codes[#codes + 1] = CODE[st.name] end
    T.eq(table.concat(codes), ref[ch], ch .. " 的笔顺")
  end
end)

T.case("每一笔的走向符合笔画类型", function()
  for _, ch in ipairs(S.order) do
    for i, st in ipairs(S[ch].strokes) do
      local a, z = st.pts[1], st.pts[#st.pts]
      local dx, dy = z[1] - a[1], z[2] - a[2]
      local tag = ch .. "第" .. i .. "笔" .. st.name
      if st.name == "横" then T.ok(dx > 0.3 and math.abs(dy) < 0.05, tag .. " 自左向右")
      elseif st.name == "竖" then T.ok(dy > 0.3 and math.abs(dx) < 0.05, tag .. " 自上而下")
      elseif st.name == "撇" then T.ok(dx < 0 and dy > 0, tag .. " 向左下")
      else T.ok(dx > 0 and dy > 0, tag .. " 向右下") end
      for _, p in ipairs(st.pts) do T.ok(p[1] >= 0 and p[1] <= 1 and p[2] >= 0 and p[2] <= 1, tag .. " 在格内") end
    end
  end
end)

T.case("照着模板描能通过，带点手抖也能通过", function()
  local r = U.rng(42)
  for _, ch in ipairs(S.order) do
    local sess = Stroke.session(S[ch])
    while not sess:finished() do
      local st = sess:current()
      local drawn = {}
      for _, p in ipairs(U.resample(st.pts, 12)) do
        drawn[#drawn + 1] = { p[1] + r:range(-0.03, 0.03), p[2] + r:range(-0.03, 0.03) }
      end
      local ok, info = sess:submit(drawn)
      T.ok(ok, ch .. " " .. st.name .. " " .. tostring(info.reason))
      if not ok then sess:assist() end
    end
    T.ok(sess:score() > 0.3, ch .. " 得分")
  end
end)

T.case("写反方向、乱画、太短都不算", function()
  local st = S["下"].strokes[1].pts      -- 横
  local rev = { { st[2][1], st[2][2] }, { st[1][1], st[1][2] } }
  local ok, info = Stroke.evaluate(st, rev)
  T.ok(not ok); T.eq(info.reason, "reverse")
  ok, info = Stroke.evaluate(st, { { 0.15, 0.22 }, { 0.5, 0.8 }, { 0.85, 0.22 } })
  T.ok(not ok); T.eq(info.reason, "shape")
  ok, info = Stroke.evaluate(st, { { 0.15, 0.22 }, { 0.16, 0.22 } })
  T.ok(not ok); T.eq(info.reason, "short")
  ok, info = Stroke.evaluate(st, { { 0.5, 0.6 }, { 0.85, 0.22 } })
  T.ok(not ok); T.eq(info.reason, "start")
end)

T.case("连错三次后可以请师傅带一笔", function()
  local sess = Stroke.session(S["平"])
  for _ = 1, 3 do sess:submit({ { 0, 0 }, { 0.01, 0.9 } }) end
  T.eq(sess.fails, 3)
  T.ok(sess:assist())
  T.eq(sess.idx, 2)
  T.eq(sess.fails, 0)
end)
