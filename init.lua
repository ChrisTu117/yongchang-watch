-- SPDX-License-Identifier: AGPL-3.0-only
-- Dora SSR 1.10 入口（Dora 平台兼容版本）。
-- 本目录根部的 main.lua / conf.lua 是一个标准 LÖVE 11.5 项目；这里把它放进 LoveNode 运行，
-- 并按 Dora 官方 love-game-development 指南用 2D 摄像机做等比适配（游戏内不再重复缩放）。
-- 本文件只用 Dora 接口，游戏代码只用 love.* 接口，两边互不引用。
local _ENV = Dora

local game = LoveNode("main.lua")
if not game then
  print("永昌守望：LoveNode 创建失败。请使用 Dora SSR 1.10 或更新版本运行本项目根目录的 init.lua。")
  return
end
if game.lastError ~= "" then print("永昌守望：" .. game.lastError) end

game:addTo(Director.entry)

local camera = tolua.cast(Director.currentCamera, "Camera2D")
local function fit()
  if camera and game.width > 0 and game.height > 0 then
    camera.zoom = math.min(View.size.width / game.width, View.size.height / game.height)
  end
end
fit()
Director.entry:onAppChange(function(settingName)
  if settingName == "Size" then fit() end
end)
