-- SPDX-License-Identifier: AGPL-3.0-only
-- Dora SSR 1.10 入口（Dora 平台兼容版本）。
-- 本目录根部的 main.lua / conf.lua 是一个标准 LÖVE 11.5 项目；这里把它放进 LoveNode 运行，
-- 并按 Dora 官方 love-game-development 指南用 2D 摄像机做等比适配（游戏内不再重复缩放），
-- 同时给 Dora 的底部工具栏留出位置。
-- 本文件只用 Dora 接口，游戏代码只用 love.* 接口，两边互不引用。
local _ENV = Dora

local game = LoveNode("main.lua")
if not game then
  print("永昌守望：LoveNode 创建失败。请使用 Dora SSR 1.10 或更新版本运行本项目根目录的 init.lua。")
  return
end
if game.lastError ~= "" then print("永昌守望：" .. game.lastError) end

game:addTo(Director.entry)

-- 在 Dora 里运行项目时，底部有一条 50 高的开发工具栏（Quit / Reload，默认显示，Ctrl+/ 可切换；
-- 见 Dora 自带的 Assets/Script/Dev/Entry.yue）。把游戏放在工具栏上方，避免按钮和底栏被盖住。
local FOOTER = 50
local camera = tolua.cast(Director.currentCamera, "Camera2D")
local function fit()
  if camera and game.width > 0 and game.height > 0 then
    local vw, vh = View.size.width, View.size.height
    local reserve = vh * FOOTER / App.visualSize.height
    local zoom = math.min(vw / game.width, (vh - reserve) / game.height)
    camera.zoom = zoom
    camera.position = Vec2(0, -reserve / 2 / zoom)
  end
end
fit()
Director.entry:onAppChange(function(settingName)
  if settingName == "Size" then fit() end
end)

-- Windows 和 macOS 版 Dora 启动后显示内置 Web IDE；IDE 盖着窗口时引擎跳过绘制，逻辑和声音照常运行
-- （Dora 1.10.2 源码 Director::doRender）。从 IDE 的运行按钮启动时 IDE 会自己收起，用命令行 `Dora cli run`
-- 启动时不会，就会只有声音没有画面。这里照 Dora 自带 Script/Dev/Entry.yue 启动导入工具时的做法收起 IDE；
-- 在 Windows 上按 Ctrl+Shift+H 可以切回 IDE。
if (App.platform == "Windows" or App.platform == "macOS") and App.webIDEEnabled then
  emit("AppWebView", "/ide/hide", false)
end
