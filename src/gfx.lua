-- SPDX-License-Identifier: AGPL-3.0-only
-- 画面工具：逻辑分辨率 960x540 等比缩放；文字按实际像素大小生成字体，任何窗口尺寸都清晰。
local love = require("love")
local U = require("src.util")

local G = {}
G.W, G.H = 960, 540
G.scale, G.ox, G.oy = 1, 0, 0
G.FONT = "assets/fonts/ycw-serif.ttf"
G.fonts = {}

G.C = {
  ink = { 0.96, 0.92, 0.82 },
  dim = { 0.70, 0.68, 0.62 },
  gold = { 1.00, 0.80, 0.36 },
  red = { 0.92, 0.30, 0.24 },
  green = { 0.45, 0.82, 0.50 },
  blue = { 0.48, 0.70, 0.95 },
  panel = { 0.07, 0.08, 0.13, 0.86 },
  panelEdge = { 0.85, 0.66, 0.36, 0.9 },
}

function G.resize(w, h)
  G.scale = math.min(w / G.W, h / G.H)
  G.ox = math.floor((w - G.W * G.scale) / 2)
  G.oy = math.floor((h - G.H * G.scale) / 2)
end

function G.toLogical(x, y) return (x - G.ox) / G.scale, (y - G.oy) / G.scale end
function G.toScreen(x, y) return x * G.scale + G.ox, y * G.scale + G.oy end

-- 逻辑字号 -> 实际像素字体
function G.font(size)
  local px = math.max(8, math.floor(size * G.scale + 0.5))
  local f = G.fonts[px]
  if not f then
    local ok, font = pcall(love.graphics.newFont, G.FONT, px)
    if not ok then font = love.graphics.newFont(px) end
    G.fonts[px] = font
    f = font
  end
  return f
end

function G.textWidth(s, size) return G.font(size):getWidth(s) / G.scale end

function G.setColor(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

-- 画文字（逻辑坐标）。align: "left" / "center" / "right"；width 给了就自动折行。返回占用高度。
function G.text(str, x, y, size, color, align, width, lineGap)
  local f = G.font(size)
  local lines
  if width then
    lines = U.wrap(str, width, function(s) return f:getWidth(s) / G.scale end)
  else
    lines = { str }
  end
  local lh = size * (lineGap or 1.45)
  love.graphics.push()
  love.graphics.origin()
  love.graphics.setFont(f)
  G.setColor(color or G.C.ink)
  for i, line in ipairs(lines) do
    local lx = x
    local w = f:getWidth(line) / G.scale
    if align == "center" then lx = x - w / 2 elseif align == "right" then lx = x - w end
    local sx, sy = G.toScreen(lx, y + (i - 1) * lh)
    love.graphics.print(line, math.floor(sx + 0.5), math.floor(sy + 0.5))
  end
  love.graphics.pop()
  return #lines * lh, lines
end

-- 带描边的文字（地图上的飘字）
function G.outlined(str, x, y, size, color, align)
  local d = 1.2
  for _, o in ipairs({ { -d, 0 }, { d, 0 }, { 0, -d }, { 0, d } }) do
    G.text(str, x + o[1], y + o[2], size, { 0, 0, 0, 0.85 }, align)
  end
  G.text(str, x, y, size, color, align)
end

function G.panel(x, y, w, h, alpha)
  local c = G.C.panel
  love.graphics.setColor(c[1], c[2], c[3], alpha or c[4])
  love.graphics.rectangle("fill", x, y, w, h, 6, 6)
  G.setColor(G.C.panelEdge)
  love.graphics.setLineWidth(1.5)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 6, 6)
end

-- 按钮：{x,y,w,h,label,hot}
function G.button(b, hot)
  local base = hot and { 0.55, 0.20, 0.14, 0.95 } or { 0.22, 0.12, 0.10, 0.9 }
  love.graphics.setColor(base)
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 5, 5)
  G.setColor(hot and G.C.gold or G.C.panelEdge)
  love.graphics.setLineWidth(hot and 2 or 1.2)
  love.graphics.rectangle("line", b.x + 0.5, b.y + 0.5, b.w - 1, b.h - 1, 5, 5)
  local size = b.size or 20
  G.text(b.label, b.x + b.w / 2, b.y + (b.h - size * 1.3) / 2, size, hot and G.C.gold or G.C.ink, "center")
end

function G.inRect(px, py, r) return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h end

-- 径向渐变光斑（照明用），运行时生成
function G.lightImage()
  if G._light then return G._light end
  local n = 128
  local data = love.image.newImageData(n, n)
  for y = 0, n - 1 do
    for x = 0, n - 1 do
      local dx, dy = (x + 0.5) / n * 2 - 1, (y + 0.5) / n * 2 - 1
      local d = math.sqrt(dx * dx + dy * dy)
      local v = U.clamp(1 - d, 0, 1)
      v = v * v * (3 - 2 * v)
      data:setPixel(x, y, 1, 1, 1, v)
    end
  end
  G._light = love.graphics.newImage(data)
  return G._light
end

-- 扇形（光束）多边形顶点
function G.fan(cx, cy, r, a1, a2, segs)
  local v = { cx, cy }
  for i = 0, segs do
    local a = a1 + (a2 - a1) * i / segs
    v[#v + 1] = cx + math.cos(a) * r
    v[#v + 1] = cy + math.sin(a) * r
  end
  return v
end

function G.star(cx, cy, r, filled)
  local v = {}
  for i = 0, 9 do
    local a = -math.pi / 2 + i * math.pi / 5
    local rr = (i % 2 == 0) and r or r * 0.45
    v[#v + 1] = cx + math.cos(a) * rr
    v[#v + 1] = cy + math.sin(a) * rr
  end
  if filled then
    love.graphics.setColor(1, 0.8, 0.3)
    -- 星形是凹多边形，拆成三角形画
    for i = 0, 9 do
      local j = (i + 1) % 10
      love.graphics.polygon("fill", cx, cy, v[i * 2 + 1], v[i * 2 + 2], v[j * 2 + 1], v[j * 2 + 2])
    end
  end
  love.graphics.setColor(1, 0.8, 0.3)
  love.graphics.setLineWidth(1.5)
  love.graphics.polygon("line", v)
end

return G
