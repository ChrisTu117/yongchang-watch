-- SPDX-License-Identifier: AGPL-3.0-only
local L = require("src.data.levels")
local S = require("src.data.strokes")
local Story = require("src.data.story")

T.case("三夜各得一字，加上终章的“平”，拼成“天下太平”", function()
  local s = ""
  for i = 1, L.count do s = s .. L[i].char end
  T.eq(s .. "平", "天下太平")
  T.eq(table.concat(S.order), "天下太平")
end)

T.case("每夜前都有剧情页，每个字都有说明", function()
  for i = 1, L.count do
    T.ok(Story.before[i] and #Story.before[i] >= 2, "第" .. i .. "夜剧情")
    for _, p in ipairs(Story.before[i]) do T.ok(#p.text > 10 and #p.head > 0) end
  end
  for _, ch in ipairs(S.order) do T.ok(Story.dragon[ch] and #Story.dragon[ch].text > 10, ch) end
  T.ok(#Story.ending >= 2)
  T.ok(#Story.help >= 4)
end)

T.case("剧情里标了出处的条目，出处编号都在资料文件里", function()
  local f = io.open("docs/文化资料与出处.md", "r")
  T.ok(f ~= nil, "docs/文化资料与出处.md 存在")
  if not f then return end
  local doc = f:read("*a")
  f:close()
  local function check(src)
    if src then T.ok(doc:find("[" .. src .. "]", 1, true) ~= nil, "出处 " .. src) end
  end
  for i = 1, L.count do for _, p in ipairs(Story.before[i]) do check(p.src) end end
  for _, ch in ipairs(S.order) do check(Story.dragon[ch].src) end
  for _, p in ipairs(Story.ending) do check(p.src) end
end)

T.case("史实年份前后一致", function()
  T.ok(L[1].era:find("1559", 1, true) ~= nil)
  T.ok(L[2].era:find("1632", 1, true) ~= nil)
  T.ok(L[3].era:find("1648", 1, true) ~= nil)
end)

T.case("关卡内容与日志说法一致", function()
  local MAP = require("src.data.map")
  local function landings(lv)
    local seen = {}
    for _, wv in ipairs(L[lv].waves) do
      if wv.boat then
        local p = MAP.paths[wv.path].pts[1]
        for name, l in pairs(MAP.landings) do
          if l.x == p[1] and l.y == p[2] then seen[name] = true end
        end
      end
    end
    return seen
  end
  local l2 = landings(2)
  T.ok(l2.north and l2.mid and l2.south, "第二夜从北、中、南三处登陆")
  local hill, refugees = false, {}
  for lv = 1, L.count do
    refugees[lv] = 0
    for _, wv in ipairs(L[lv].waves) do
      if wv.kind == "refugee" then refugees[lv] = refugees[lv] + wv.n end
      if lv == 3 and wv.path:find("^hill_") then hill = true end
    end
  end
  T.ok(hill, "第三夜有从山上来的敌人")
  T.ok(refugees[3] > refugees[2] and refugees[3] > refugees[1], "第三夜百姓最多")
  T.eq(S["天"].dragon, "红龙"); T.eq(S["下"].dragon, "黄龙"); T.eq(S["太"].dragon, "蓝龙"); T.eq(S["平"].dragon, "绿龙")
  local doc = io.open("docs/文化资料与出处.md"):read("*a")
  T.ok(doc:find("红、黄两支", 1, true) ~= nil and doc:find("红黄蓝绿黑五支", 1, true) ~= nil, "龙队数量有出处")
  T.ok(doc:find("避乱我堡者何止万人", 1, true) ~= nil, "避乱万人有出处")
  T.ok(doc:find("守望同心", 1, true) ~= nil, "守望同心有出处")
end)
