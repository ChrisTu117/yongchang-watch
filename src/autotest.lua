-- SPDX-License-Identifier: AGPL-3.0-only
-- 端到端自动测试（love . --autotest）。用真实的输入入口（App.mousemoved / mousepressed / keypressed）
-- 从标题一路玩到终章，再从标题菜单退出。教学步骤用模拟的鼠标操作完成；之后的守城由测试机器人
-- （src/sim/bot.lua）调用与玩家相同的操作。结果打印到标准输出，进程退出码 0 表示全部通过。
local love = require("love")
local G = require("src.gfx")
local L = require("src.data.levels")
local S = require("src.data.strokes")
local U = require("src.util")
local Bot = require("src.sim.bot")
local World = require("src.sim.world")

local AT = { checks = {}, scenes = {}, frames = 0, real = 0, speed = 6, failed = false }
local App, Input
local co

local function check(name, ok, detail)
  AT.checks[#AT.checks + 1] = { name = name, ok = ok and true or false, detail = detail }
  print(string.format("[%s] %s%s", ok and "PASS" or "FAIL", name, detail and ("  (" .. tostring(detail) .. ")") or ""))
  if not ok then AT.failed = true end
end

-- 以下都在协程里调用；yield 返回本步的模拟时长
local function step() return coroutine.yield() end
local function wait(sec)
  local t = 0
  while t < sec do t = t + step() end
end
local function waitFor(cond, timeout, label)
  local t = 0
  while not cond() do
    t = t + step()
    if t > timeout then check("等待：" .. label, false, "超时 " .. timeout .. " 秒"); return false end
  end
  return true
end
local function move(x, y)
  local sx, sy = G.toScreen(x, y)
  App.mousemoved(sx, sy)
end
local function click(x, y)
  local sx, sy = G.toScreen(x, y)
  App.mousemoved(sx, sy)
  App.mousepressed(sx, sy, 1)
  App.mousereleased(sx, sy, 1)
end
local function clickButton(list, id)
  for _, b in ipairs(list) do
    if b.id == id then click(b.x + b.w / 2, b.y + b.h / 2); return true end
  end
  check("找到按钮 " .. id, false)
  return false
end
local function key(k) App.keypressed(k) end
-- 截图：本帧不再推进模拟，画面停在截图时的状态
local function shot(name)
  AT.shots[#AT.shots + 1] = name
  love.graphics.captureScreenshot("autotest/" .. name .. ".png")
  AT.hold = true
  step()
end

local function passStory(shotName)
  waitFor(function() return App.sceneName == "story" end, 5, "剧情页")
  wait(0.6)
  if shotName then shot(shotName) end
  for _ = 1, #App.scene.pages do key("space"); wait(0.2) end
end

local function playNight(level, withTutorial)
  waitFor(function() return App.sceneName == "battle" end, 5, "第" .. level .. "夜开始")
  local sc = App.scene
  local w = sc.world
  if withTutorial then
    check("第一夜有教学", w:tutorialActive() and w.tut.step == World.TUT.LOOK)
    shot("03-tutorial-look")
    move(880, 270)                               -- 教学 1：把光照向东边海面
    waitFor(function() return w.tut.step == World.TUT.BUILD end, 5, "教学：望向海面")
    check("教学 1：移动鼠标照向海面", w.tut.step == World.TUT.BUILD)
    local s5 = w.slots[5]
    click(s5.x, s5.y)                            -- 教学 2：点敌台安排弓手
    check("教学 2：点击敌台安排弓手", s5.tower ~= nil and s5.tower.kind == "archer")
    waitFor(function() return w.tut.step == World.TUT.OPEN end, 2, "教学：建造")
    local gw = w.gateById.W
    waitFor(function() return #w.refugees > 0 end, 10, "百姓出现")
    click(gw.x, gw.y)                            -- 教学 3：开西门
    check("教学 3：点击城门打开", gw.open)
    waitFor(function() return w.tut.step == World.TUT.CLOSE end, 40, "教学：迎百姓")
    check("教学 3：迎入百姓", w.saved >= 1, "迎入 " .. w.saved)
    click(gw.x, gw.y)                            -- 关门
    check("点击城门关闭", not gw.open)
    shot("04-tutorial-close")
  end

  local bot = Bot.new("smart")
  local tested = false
  local midShot = false
  while w.state == "playing" do
    local dt = step()
    bot:act(w, dt)
    if not w:tutorialActive() and not tested and w.t > 8 then
      tested = true
      -- 键盘与菜单：空格暂停、Esc 菜单、数字键切换、F 孔明灯
      key("space"); check("空格暂停", sc.paused == true)
      local t0 = w.t
      wait(0.5)
      check("暂停时时间不走", w.t == t0)
      key("space"); check("空格继续", sc.paused == false)
      key("escape"); check("Esc 打开菜单", sc.menu ~= nil)
      clickButton(sc:menuButtons(), "resume"); check("菜单：继续", sc.menu == nil)
      key("2"); check("按 2 选鸟铳", sc.selected == "gunner")
      key("1"); check("按 1 选弓手", sc.selected == "archer")
      local cd0 = w.lanternCd
      move(700, 120); key("f")
      check("F 放孔明灯", w.lantern ~= nil or cd0 > 0)
    end
    if not midShot and w.t > w.duration * 0.55 then
      midShot = true
      shot(string.format("05-night%d", level))
      if level == 2 then
        sc.coverMode = true
        shot("cover")
        sc.coverMode = false
      end
    end
  end
  waitFor(function() return sc.result ~= nil end, 5, "结算面板")
  check(string.format("第%d夜守住", level), w.state == "won",
    string.format("堡安 %d，迎入 %d/%d，击退 %d", w.anning, w.saved, w.refugeesSpawned, w.kills))
  if level == 1 then shot("06-result") end
  if sc.result.won then clickButton(sc.result.buttons, "dragon") end
end

local function traceChar(ch, testWrong)
  waitFor(function() return App.sceneName == "dragon" and App.scene.char == ch end, 5, "舞龙显字 " .. ch)
  local sc = App.scene
  local box = { x = 470, y = 110, s = 330 }
  local function drag(pts)
    local first = pts[1]
    local sx, sy = G.toScreen(box.x + first[1] * box.s, box.y + first[2] * box.s)
    App.mousemoved(sx, sy); App.mousepressed(sx, sy, 1)
    for i = 2, #pts do
      local x, y = G.toScreen(box.x + pts[i][1] * box.s, box.y + pts[i][2] * box.s)
      App.mousemoved(x, y)
      step()
    end
    local last = pts[#pts]
    sx, sy = G.toScreen(box.x + last[1] * box.s, box.y + last[2] * box.s)
    App.mousereleased(sx, sy, 1)
    step()
  end
  if testWrong then
    local st = S[ch].strokes[1].pts
    drag(U.resample({ st[#st], st[1] }, 10))     -- 故意写反
    check("写反的笔画不算", sc.session.idx == 1 and sc.session.fails == 1)
  end
  local n = #S[ch].strokes
  for i = 1, n do
    local st = sc.session:current()
    drag(U.resample(st.pts, 14))
    if i == 2 and testWrong then shot("07-dragon") end
  end
  check("描完「" .. ch .. "」", sc.session:finished(), "得分 " .. string.format("%.2f", sc.session:score()))
  wait(0.5)
  click(sc.nextBtn.x + 10, sc.nextBtn.y + 10)
end

-- Dora 的 LoveNode 把鼠标点击作为触摸回调送来；这里走真正的输入转接模块 src/input.lua
local function touchClick(id, x, y)
  local sx, sy = G.toScreen(x, y)
  Input.touchpressed(id, sx, sy)
  step()
  Input.touchreleased(id, sx, sy)
  step()
end

local function inputChecks()
  local title = App.scene
  local help = title:button("help")
  touchClick("t1", help.x + help.w / 2, help.y + help.h / 2)
  check("Dora 式触摸点击：进入操作说明", App.sceneName == "help")
  local back = App.scene.back
  touchClick("t2", back.x + back.w / 2, back.y + back.h / 2)
  check("Dora 式触摸点击：返回标题", App.sceneName == "title")
  -- 同一次点击被鼠标和触摸两条路各送一次时，只处理一次；触摸屏的 istouch 鼠标回调被忽略
  local count, orig = 0, App.mousepressed
  App.mousepressed = function(...) count = count + 1 end
  local sx, sy = G.toScreen(40, 40)
  Input.mousepressed(sx, sy, 1, false)
  Input.touchpressed("t3", sx, sy)
  Input.touchreleased("t3", sx, sy)
  Input.mousepressed(sx + 100, sy, 1, true)
  App.mousepressed = orig
  check("鼠标与触摸重复送来的同一次点击只处理一次", count == 1, "处理了 " .. count .. " 次")
  wait(0.2)
end

local function script()
  waitFor(function() return App.sceneName == "title" end, 5, "标题")
  wait(0.5)
  shot("01-title")
  inputChecks()
  clickButton(App.scene.buttons, "start")
  passStory("02-story")
  playNight(1, true)
  traceChar("天", true)
  passStory()
  playNight(2, false)
  traceChar("下", false)
  passStory()
  playNight(3, false)
  traceChar("太", false)
  traceChar("平", false)
  waitFor(function() return App.sceneName == "ending" end, 5, "终章")
  wait(9)
  shot("08-ending")
  click(App.scene.btn.x + 20, App.scene.btn.y + 10)
  waitFor(function() return App.sceneName == "title" end, 5, "回到标题")
  check("通关后存档解锁终章", App.save.unlocked == 4, "unlocked=" .. App.save.unlocked)
  wait(0.3)
  local seen = table.concat(AT.scenes, ",")
  for _, need in ipairs({ "title", "story", "battle", "dragon", "ending" }) do
    check("经过场景 " .. need, seen:find(need, 1, true) ~= nil)
  end
  AT.exitVia = "menu"
  clickButton(App.scene.buttons, "quit")         -- 从标题菜单正常退出
end

function AT.start(app, _, input)
  App, Input = app, input
  AT.shots = {}
  love.filesystem.createDirectory("autotest")
  App.onScene = function(name) AT.scenes[#AT.scenes + 1] = name end
  AT.scenes[1] = App.sceneName
  love.errorhandler = function(msg)
    print("[FAIL] Lua 错误：" .. tostring(msg))
    print(debug.traceback())
    io.stdout:flush()
    os.exit(3)
  end
  co = coroutine.create(script)
  print("AUTOTEST start, save dir: " .. love.filesystem.getSaveDirectory())
end

function AT.update(dt)
  AT.frames = AT.frames + 1
  AT.real = AT.real + dt
  if AT.real > 900 then
    print("[FAIL] 自动测试超时")
    os.exit(4)
  end
  if App.quitting then return end
  local sim = 1 / 30
  AT.hold = false
  for _ = 1, AT.speed do
    App.update(sim)
    if coroutine.status(co) ~= "dead" then
      local ok, err = coroutine.resume(co, sim)
      if not ok then
        print("[FAIL] 测试脚本出错：" .. tostring(err))
        print(debug.traceback(co))
        os.exit(5)
      end
    end
    if App.quitting or AT.hold then break end
  end
end

function AT.afterDraw() end

function AT.onQuit()
  local passed, total = 0, #AT.checks
  for _, c in ipairs(AT.checks) do if c.ok then passed = passed + 1 end end
  local lines = { string.format("checks %d/%d passed", passed, total), "exit_via=" .. tostring(AT.exitVia),
                  "frames=" .. AT.frames, string.format("real_seconds=%.1f", AT.real),
                  "screenshots=" .. table.concat(AT.shots, ",") }
  for _, c in ipairs(AT.checks) do lines[#lines + 1] = (c.ok and "PASS " or "FAIL ") .. c.name .. (c.detail and ("  " .. c.detail) or "") end
  love.filesystem.write("autotest/result.txt", table.concat(lines, "\n") .. "\n")
  local ok = (not AT.failed) and AT.exitVia == "menu" and total > 0
  print(ok and "AUTOTEST PASS" or "AUTOTEST FAIL")
  io.stdout:flush()
  if not ok then os.exit(1) end
end

return AT
