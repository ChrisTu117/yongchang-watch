-- SPDX-License-Identifier: AGPL-3.0-only
-- 通用小工具。只用 Lua 5.1 与 Lua 5.5 都支持的写法（LÖVE 用 LuaJIT，Dora 用 Lua 5.5）。
local U = {}

function U.clamp(x, a, b)
  if x < a then return a elseif x > b then return b end
  return x
end

function U.lerp(a, b, t) return a + (b - a) * t end

function U.dist2(ax, ay, bx, by)
  local dx, dy = bx - ax, by - ay
  return dx * dx + dy * dy
end

function U.dist(ax, ay, bx, by) return math.sqrt(U.dist2(ax, ay, bx, by)) end

-- 把角度差规整到 [-pi, pi]
function U.angdiff(a, b)
  local d = (a - b) % (2 * math.pi)
  if d > math.pi then d = d - 2 * math.pi end
  return d
end

function U.atan2(y, x)
  -- Lua 5.3+ 去掉了 math.atan2；math.atan(y, x) 在 5.1 里只取一个参数，所以两边分开处理。
  if math.atan2 then return math.atan2(y, x) end
  return math.atan(y, x)
end

-- 确定性随机数（Park-Miller）。乘积小于 2^53，LuaJIT 的浮点和 Lua 5.5 的整数算出来完全一样。
local RNG = {}
RNG.__index = RNG
function U.rng(seed)
  local s = math.floor(seed or 1) % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return setmetatable({ s = s }, RNG)
end
function RNG:next()
  self.s = (self.s * 16807) % 2147483647
  return self.s / 2147483647
end
function RNG:range(a, b) return a + (b - a) * self:next() end
function RNG:int(a, b) return a + math.floor(self:next() * (b - a + 1)) end

-- 整数显示：避免 Lua 5.5 把 3.0 打印成 "3.0"
function U.int(x) return string.format("%d", math.floor(x + 0.5)) end

-- UTF-8 拆字（不依赖 utf8 库，两种 Lua 都能用）
function U.chars(s)
  local out, i, n = {}, 1, #s
  while i <= n do
    local c = s:byte(i)
    local len = 1
    if c >= 240 then len = 4 elseif c >= 224 then len = 3 elseif c >= 192 then len = 2 end
    out[#out + 1] = s:sub(i, i + len - 1)
    i = i + len
  end
  return out
end

-- 按像素宽度折行。measure(str) 返回宽度。中文逐字可断，英文单词和数字不拆；
-- 行首不放句读和右括号，行末不放左括号（左括号和后面的字连在一起）。
local CLOSERS = { ["，"] = true, ["。"] = true, ["、"] = true, ["；"] = true, ["："] = true,
  ["！"] = true, ["？"] = true, ["）"] = true, ["》"] = true, ["」"] = true, ["』"] = true, ["”"] = true }
local OPENERS = { ["（"] = true, ["《"] = true, ["「"] = true, ["『"] = true, ["“"] = true,
  ["【"] = true, ["〔"] = true }

local function tokens(para)
  local out, word, open = {}, "", ""
  local function push(t) out[#out + 1] = open .. t; open = "" end
  for _, ch in ipairs(U.chars(para)) do
    if #ch == 1 and ch ~= " " then
      word = word .. ch
    else
      if word ~= "" then push(word); word = "" end
      if OPENERS[ch] then open = open .. ch else push(ch) end
    end
  end
  if word ~= "" then push(word) end
  if open ~= "" then out[#out + 1] = open end
  return out
end

function U.wrap(text, width, measure)
  local lines = {}
  for para in (text .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for _, tok in ipairs(tokens(para)) do
      local try = line .. tok
      if line == "" or measure(try) <= width or CLOSERS[tok] then
        line = try
      else
        lines[#lines + 1] = line
        line = (tok == " ") and "" or tok
      end
    end
    lines[#lines + 1] = line
  end
  return lines
end

function U.copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = U.copy(v) end
  return o
end

-- 折线长度与等距重采样（笔画评分用）
function U.polylen(pts)
  local L = 0
  for i = 2, #pts do L = L + U.dist(pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]) end
  return L
end

function U.resample(pts, n)
  local out = {}
  if #pts == 0 then return out end
  if #pts == 1 then
    for k = 1, n do out[k] = { pts[1][1], pts[1][2] } end
    return out
  end
  local total = U.polylen(pts)
  if total <= 0 then
    for k = 1, n do out[k] = { pts[1][1], pts[1][2] } end
    return out
  end
  local step = total / (n - 1)
  out[1] = { pts[1][1], pts[1][2] }
  local seg, segPos, acc = 2, 0, 0
  for k = 2, n - 1 do
    local target = step * (k - 1)
    while seg <= #pts do
      local a, b = pts[seg - 1], pts[seg]
      local sl = U.dist(a[1], a[2], b[1], b[2])
      if acc + sl >= target then
        local t = (sl > 0) and (target - acc) / sl or 0
        out[k] = { U.lerp(a[1], b[1], t), U.lerp(a[2], b[2], t) }
        break
      end
      acc = acc + sl
      seg = seg + 1
    end
    if not out[k] then out[k] = { pts[#pts][1], pts[#pts][2] } end
  end
  out[n] = { pts[#pts][1], pts[#pts][2] }
  return out
end

return U
