-- SPDX-License-Identifier: AGPL-3.0-only
local U = require("src.util")

T.case("rng 在两种 Lua 里结果一致", function()
  -- Park-Miller 的已知序列：种子 1 的前三个值是 16807、282475249、1622650073
  local r = U.rng(1)
  r:next(); T.eq(r.s, 16807)
  r:next(); T.eq(r.s, 282475249)
  r:next(); T.eq(r.s, 1622650073)
  for _ = 1, 100 do local x = r:next(); T.ok(x > 0 and x < 1) end
end)

T.case("整数显示不带 .0", function()
  T.eq(U.int(3.0), "3")
  T.eq(U.int(2.6), "3")
  T.eq(U.int(-0.2), "0")
end)

T.case("UTF-8 拆字", function()
  local c = U.chars("天下A平")
  T.eq(#c, 4)
  T.eq(c[1], "天"); T.eq(c[3], "A"); T.eq(c[4], "平")
end)

T.case("折行：中文逐字断，标点不到行首，英文不拆", function()
  local m = function(s) return #U.chars(s) end
  local lines = U.wrap("一二三四五，六七", 5, m)
  T.eq(lines[1], "一二三四五，")
  T.eq(lines[2], "六七")
  lines = U.wrap("ab cdef", 4, m)
  T.eq(lines[1], "ab ")
  T.eq(lines[2], "cdef")
  lines = U.wrap("第一段\n第二段", 10, m)
  T.eq(#lines, 2)
end)

T.case("等距重采样", function()
  local pts = U.resample({ { 0, 0 }, { 1, 0 } }, 5)
  T.eq(#pts, 5)
  T.near(pts[3][1], 0.5); T.near(pts[5][1], 1)
  pts = U.resample({ { 0, 0 }, { 1, 0 }, { 1, 1 } }, 3)
  T.near(pts[2][1], 1); T.near(pts[2][2], 0)
end)

T.case("角度差", function()
  T.near(U.angdiff(0.1, 2 * math.pi - 0.1), 0.2, 1e-9)
  T.near(math.abs(U.angdiff(math.pi, -math.pi)), 0, 1e-9)
end)
