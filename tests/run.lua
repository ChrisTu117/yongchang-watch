-- SPDX-License-Identifier: AGPL-3.0-only
-- 纯 Lua 单元测试入口。用法（在仓库根目录）：
--   luajit tests/run.lua        （LÖVE 11.5 用的 LuaJIT）
--   lua5.5 tests/run.lua        （Dora SSR 1.10 的 LoveNode 用的 Lua 5.5）
package.path = "./?.lua;" .. package.path

local T = { passed = 0, failed = 0, current = "" }
_G.T = T

local function fmt(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

function T.ok(cond, msg)
  if cond then
    T.passed = T.passed + 1
  else
    T.failed = T.failed + 1
    print("  FAIL [" .. T.current .. "] " .. (msg or "expected truthy"))
  end
end

function T.eq(a, b, msg)
  T.ok(a == b, (msg or "") .. " expected " .. fmt(b) .. " got " .. fmt(a))
end

function T.near(a, b, eps, msg)
  T.ok(math.abs(a - b) <= (eps or 1e-6), (msg or "") .. " expected ~" .. fmt(b) .. " got " .. fmt(a))
end

function T.case(name, fn)
  T.current = name
  local ok, err = pcall(fn)
  if not ok then
    T.failed = T.failed + 1
    print("  ERROR [" .. name .. "] " .. tostring(err))
  end
end

local files = { "test_util", "test_world", "test_stroke", "test_content", "test_balance" }
local version = (jit and jit.version) or _VERSION
print("Lua: " .. version)
for _, f in ipairs(files) do
  local before = T.failed
  dofile("tests/" .. f .. ".lua")
  print(string.format("%-14s %s", f, T.failed == before and "ok" or "FAILED"))
end
print(string.format("passed %d, failed %d", T.passed, T.failed))
os.exit(T.failed == 0 and 0 or 1)
