-- SPDX-License-Identifier: AGPL-3.0-only
-- 用测试机器人把三夜各打一遍，输出每夜结果的“指纹”。LuaJIT 和 Lua 5.5 的输出应完全相同。
-- 用法（仓库根目录）：luajit tools/sim_signature.lua ；lua5.5 tools/sim_signature.lua
package.path = "./?.lua;" .. package.path
local World = require("src.sim.world")
local Bot = require("src.sim.bot")
local L = require("src.data.levels")
for lv = 1, L.count do
  local w = World.new(L[lv], {})
  local b = Bot.new("smart")
  local events = 0
  while w.state == "playing" do
    b:act(w, 1 / 30); w:update(1 / 30)
    events = events + #w:drainEvents()
  end
  local towers = {}
  for _, s in ipairs(w.slots) do towers[#towers + 1] = s.tower and (s.tower.kind:sub(1, 1) .. s.tower.level) or "-" end
  print(string.format("night%d %s anning=%d saved=%d/%d lost=%d kills=%d entered=%d minli=%d events=%d t=%.4f towers=%s",
    lv, w.state, w.anning, w.saved, w.refugeesSpawned, w.lost, w.kills, w.entered, w.minli, events, w.t,
    table.concat(towers, ",")))
end
