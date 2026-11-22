-- SPDX-License-Identifier: AGPL-3.0-only
-- 演示视频的录制驱动（只在 tools/record_demo.sh 里用，不进游戏发行包）。
-- 和 src/autotest.lua 一样，通过真实的输入入口（App.mousemoved / mousepressed / keypressed）操作游戏：
-- 教学部分由脚本像真人一样移动鼠标、点击；之后的守城交给测试机器人 src/sim/bot.lua。
-- 游戏按固定步长 1/30 秒推进，每一帧截图写进管道交给 ffmpeg，所以画面不受机器快慢影响。
-- 声音不在这里录：每次播放音效、切换音乐都记一行事件，由 tools/mix_demo_audio.py 按帧号混成音轨；
-- 字幕也记成事件，由同一脚本生成 ASS 字幕。
local love = require("love")
local G = require("src.gfx")
local A = require("src.audio")
local U = require("src.util")
local Bot = require("src.sim.bot")
local World = require("src.sim.world")
local App = require("src.app")

local FPS = 30
local DT = 1 / FPS
local SKIP_STEPS = 30          -- 跳过的段落每帧推进 1 秒游戏时间，不截图
local FADE = 12                -- 淡出淡入的帧数

local D = { frame = 0, capturing = true, fade = 0, blackout = false, cursor = nil, failed = false }
local co, pipe

local function ev(...)
  local parts = { ... }
  for i = 1, #parts do parts[i] = tostring(parts[i]) end
  io.stdout:write("DEMOEV\t" .. table.concat(parts, "\t") .. "\n")
  io.stdout:flush()
end
local function fail(msg) D.failed = true; ev("fail", D.frame, msg) end

-- 以下在协程里调用；每次 step() 推进一个 1/30 秒
local function step() return coroutine.yield() end
local function wait(sec) for _ = 1, math.floor(sec * FPS + 0.5) do step() end end
local function waitFor(cond, timeout, label)
  local t = 0
  while not cond() do
    t = t + step()
    if t > timeout then fail("等待超时：" .. label); return false end
  end
  return true
end
-- 字幕：从当前帧开始显示 sec 秒
local function cap(text, sec) ev("cap", D.frame, math.floor(sec * FPS + 0.5), text) end

local function setCursor(sx, sy) D.cursor = { sx, sy } end
local function moveScreen(sx, sy) setCursor(sx, sy); App.mousemoved(sx, sy) end
local function move(x, y) local sx, sy = G.toScreen(x, y); moveScreen(sx, sy) end
local function cursorLogical()
  if not D.cursor then return 480, 300 end
  return G.toLogical(D.cursor[1], D.cursor[2])
end
-- 像真人一样把鼠标移过去（先快后慢）
local function glide(x, y, sec)
  local x0, y0 = cursorLogical()
  local n = math.max(1, math.floor(sec * FPS + 0.5))
  for i = 1, n do
    local k = i / n
    k = 1 - (1 - k) ^ 3
    move(x0 + (x - x0) * k, y0 + (y - y0) * k)
    step()
  end
end
local function press(x, y)
  local sx, sy = G.toScreen(x, y)
  moveScreen(sx, sy)
  App.mousepressed(sx, sy, 1)
  App.mousereleased(sx, sy, 1)
end
local function clickAt(x, y, sec) glide(x, y, sec or 0.5); press(x, y); step() end
local function clickButton(list, id, sec)
  for _, b in ipairs(list) do
    if b.id == id then clickAt(b.x + b.w / 2, b.y + b.h / 2, sec); return true end
  end
  fail("找不到按钮 " .. id)
  return false
end
local function key(k) App.keypressed(k) end

-- 淡出 → 不截图快进到 cond 成立 → 淡入
local function fadeOut()
  for i = 1, FADE do D.fade = i / FADE; step() end
end
local function fadeIn()
  for i = FADE - 1, 0, -1 do D.fade = i / FADE; step() end
end
local function skipUntil(cond, timeout, label, each)
  fadeOut()
  D.capturing = false
  local t = 0
  while not cond() do
    local dt = step()
    if each then each(dt) end
    t = t + dt
    if t > timeout then fail("快进超时：" .. label); break end
  end
  D.capturing = true
  ev("cut", D.frame)
  fadeIn()
end

-- 机器人守城。机器人原本直接设置光束方向；这里把它要照的位置变成平滑的鼠标移动，
-- 再经 App.mousemoved 交给游戏，和玩家移动鼠标一样。
local function botStep(w, bot, dt)
  local want
  w.aim = function(_, x, y) want = { x, y } end
  bot:act(w, dt)
  w.aim = nil
  if want then
    local x, y = cursorLogical()
    local dx, dy = want[1] - x, want[2] - y
    local d = math.sqrt(dx * dx + dy * dy)
    local k = math.min(1, 10 * dt)
    local maxStep = 1300 * dt
    if d * k > maxStep then k = maxStep / d end
    move(x + dx * k, y + dy * k)
  end
end
local function botPlay(w, bot, sec)
  for _ = 1, math.floor(sec * FPS + 0.5) do
    if w.state ~= "playing" then return end
    botStep(w, bot, step())
  end
end

local function startCapture()
  if D.capturing then return end
  D.capturing = true
  ev("cut", D.frame)
  D.fade = 1
  fadeIn()
end
local function stopCapture()
  if not D.capturing then return end
  fadeOut()
  D.capturing = false
end

-- 剧情页：show[i] 是第 i 页展示的秒数；不展示的页淡出后直接翻过
local function storyPages(show)
  waitFor(function() return App.sceneName == "story" end, 5, "剧情页")
  local sc = App.scene
  for i = 1, #sc.pages do
    if show[i] then
      startCapture()
      if show.caps and show.caps[i] then cap(show.caps[i], show[i]) end
      wait(show[i])
    else
      stopCapture()
    end
    key("space")
    step()
  end
end

local function nightEnd(w, bot, sc)
  -- 天亮前 5 秒恢复录制，看到天亮和结算
  skipUntil(function() return w.state ~= "playing" or w.t > w.duration - 5 end, 400, "天亮前",
    function(dt) botStep(w, bot, dt) end)
  while w.state == "playing" do botStep(w, bot, step()) end
  waitFor(function() return sc.result ~= nil end, 6, "结算面板")
  if w.state ~= "won" then fail("没守住：第 " .. tostring(sc.levelIndex) .. " 夜") end
  ev("night", D.frame, sc.levelIndex or "?", w.state, w.anning, w.saved, w.kills)
end

local function traceChar(ch, opts)
  waitFor(function() return App.sceneName == "dragon" and App.scene.char == ch end, 6, "舞龙显字 " .. ch)
  local sc = App.scene
  local box = { x = 470, y = 110, s = 330 }
  if opts.caption then cap(opts.caption, opts.capSec or 6) end
  wait(opts.lead or 1.2)
  while not sc.session:finished() do
    local st = sc.session:current()
    local pts = U.resample(st.pts, 18)
    local p1 = pts[1]
    glide(box.x + p1[1] * box.s, box.y + p1[2] * box.s, 0.35)
    local sx, sy = G.toScreen(box.x + p1[1] * box.s, box.y + p1[2] * box.s)
    App.mousepressed(sx, sy, 1)
    for i = 2, #pts do
      move(box.x + pts[i][1] * box.s, box.y + pts[i][2] * box.s)
      step()
    end
    local last = pts[#pts]
    sx, sy = G.toScreen(box.x + last[1] * box.s, box.y + last[2] * box.s)
    App.mousereleased(sx, sy, 1)
    wait(0.25)
    if sc.session.fails > 2 then fail("描字失败：" .. ch); break end
  end
  wait(opts.hold or 2.5)
  clickAt(sc.nextBtn.x + sc.nextBtn.w / 2, sc.nextBtn.y + sc.nextBtn.h / 2, 0.5)
end

local function script()
  waitFor(function() return App.sceneName == "title" end, 5, "标题")
  move(480, 470)
  cap("《永昌守望》  2026 开源游戏开发大赛参赛作品 · 主题「守·望」", 5.5)
  wait(5.5)
  clickButton(App.scene.buttons, "start", 0.7)

  -- 第一夜剧情：第 1 页和第 3 页
  storyPages({ [1] = 5.5, [3] = 5.5,
    caps = { [1] = "明代温州永嘉场，乡人为抵御倭寇筑起永昌堡", [3] = "你是敌台上的守望人" } })

  waitFor(function() return App.sceneName == "battle" end, 6, "第一夜")
  local sc = App.scene
  local w = sc.world
  if not (w:tutorialActive() and w.tut.step == World.TUT.LOOK) then fail("第一夜没有教学") end
  wait(1.5)
  cap("移动鼠标，光束跟着转：你望向哪里，光就照到哪里", 5)
  glide(860, 300, 1.6)
  waitFor(function() return w.tut.step == World.TUT.BUILD end, 6, "教学：望向海面")
  glide(880, 250, 1.2)
  wait(2.2)
  cap("点城墙上的敌台，安排弓手；再点一次可以升级", 4.5)
  wait(1.2)
  local s5 = w.slots[5]
  clickAt(s5.x, s5.y, 0.9)
  if not (s5.tower and s5.tower.kind == "archer") then fail("教学：没有建成弓手") end
  waitFor(function() return w.tut.step == World.TUT.OPEN end, 3, "教学：开门")
  wait(2.5)
  local gw = w.gateById.W
  waitFor(function() return #w.refugees > 0 end, 12, "百姓出现")
  cap("乡亲走到门前会喊“开门”：开门迎进来，每人给 2 点民力", 6)
  wait(1.5)
  clickAt(gw.x, gw.y, 1.0)
  if not gw.open then fail("教学：西门没打开") end
  waitFor(function() return w.tut.step == World.TUT.CLOSE end, 40, "教学：迎百姓")
  cap("敌人靠近时，记得关门", 3.5)
  wait(1.0)
  clickAt(gw.x, gw.y, 0.6)
  if gw.open then fail("教学：西门没关上") end
  wait(2)

  local bot = Bot.new("smart")
  cap("守城单位只打得中被照亮的敌人", 5)
  botPlay(w, bot, 6)
  cap("按 1、2、3 切换弓手、鸟铳、烽火；烽火不攻击，长久照亮周围", 6)
  botPlay(w, bot, 6)
  if w.lanternCd <= 0 then
    cap("按 F 放孔明灯，照亮远处一大片", 4.5)
    glide(760, 200, 0.9)
    key("f")
    botPlay(w, bot, 3.5)
  end
  botPlay(w, bot, 6)
  nightEnd(w, bot, sc)
  cap("守住第一夜", 3)
  wait(3)
  clickButton(sc.result.buttons, "dragon", 0.8)

  traceChar("天", { caption = "每守住一夜，用龙湾宁村的拼字龙灯按笔顺描出一个字", capSec = 7 })

  -- 第二夜
  storyPages({ [2] = 5, caps = { [2] = "第二夜：崇祯五年（1632），海盗刘香围堡" } })
  waitFor(function() return App.sceneName == "battle" end, 6, "第二夜")
  sc = App.scene; w = sc.world
  bot = Bot.new("smart")
  skipUntil(function() return w.state ~= "playing" or w.t > 55 end, 300, "第二夜中段",
    function(dt) botStep(w, bot, dt) end)
  cap("城门被攻破后，点它花民力修好；东门有瓮城，更耐砸", 6)
  botPlay(w, bot, 14)
  nightEnd(w, bot, sc)
  wait(2.5)
  clickButton(sc.result.buttons, "dragon", 0.8)
  traceChar("下", { lead = 0.6, hold = 1.5 })

  -- 第三夜
  storyPages({ [2] = 5, caps = { [2] = "第三夜：顺治五年（1648），何兆龙来犯，避乱者万人" } })
  waitFor(function() return App.sceneName == "battle" end, 6, "第三夜")
  sc = App.scene; w = sc.world
  bot = Bot.new("smart")
  skipUntil(function() return w.state ~= "playing" or w.t > 70 end, 300, "第三夜中段",
    function(dt) botStep(w, bot, dt) end)
  cap("堡内农田屯田，每 12 秒 1 点民力；迎进来的乡亲越多，民力越足", 6)
  botPlay(w, bot, 14)
  nightEnd(w, bot, sc)
  wait(2.5)
  clickButton(sc.result.buttons, "dragon", 0.8)

  -- “太”快进，终章“平”完整展示
  stopCapture()
  waitFor(function() return App.sceneName == "dragon" and App.scene.char == "太" end, 6, "太")
  local dsc = App.scene
  local function sp(p) return G.toScreen(470 + p[1] * 330, 110 + p[2] * 330) end
  while not dsc.session:finished() do
    local pts = U.resample(dsc.session:current().pts, 14)
    local sx, sy = sp(pts[1])
    App.mousepressed(sx, sy, 1)
    for i = 2, #pts do sx, sy = sp(pts[i]); moveScreen(sx, sy); step() end
    App.mousereleased(sx, sy, 1)
    step()
    if dsc.session.fails > 2 then fail("描字失败：太"); break end
  end
  wait(0.5)
  press(dsc.nextBtn.x + 10, dsc.nextBtn.y + 10)
  waitFor(function() return App.sceneName == "dragon" and App.scene.char == "平" end, 6, "平")
  startCapture()
  traceChar("平", { caption = "三夜加终章，拼成“天下太平”", capSec = 6, lead = 1.0, hold = 3 })

  waitFor(function() return App.sceneName == "ending" end, 6, "终章")
  move(480, 600)
  wait(13)
  -- 片尾字卡（文字由 ASS 字幕叠加）
  fadeOut()
  D.blackout = true
  ev("card", D.frame, 7 * FPS)
  D.fade = 0
  wait(7)
  ev("end", D.frame)
  D.done = true
end

function D.start()
  local path = os.getenv("DEMO_FIFO")
  pipe = assert(io.open(path, "wb"), "无法打开帧管道 " .. tostring(path))
  local h = love.graphics.getHeight()
  -- 底部留一条字幕带：游戏画面放在上方，字幕不挡游戏的底栏
  local band = math.floor(h / 10)
  G.resize(love.graphics.getWidth(), h - band)
  ev("start", love.graphics.getWidth(), h, FPS, band)
  love.mouse.setVisible(false)
  -- 声音只记事件；音效、音乐的实际混音由 tools/mix_demo_audio.py 完成
  A.play = function(name, vol, pitch)
    if A.muted then return end
    if D.capturing then ev("sfx", D.frame, name, vol or 1, pitch or 1) end
  end
  -- 标题音乐在接管之前就开始了，补记一行
  if A.musicName then ev("music", 0, A.musicName, 0.55) end
  local playMusic = A.playMusic
  A.playMusic = function(name, vol)
    if A.musicName ~= name then ev("music", D.frame, name, vol or 0.55) end
    return playMusic(name, vol)
  end
  co = coroutine.create(script)
end

function D.update()
  local steps = D.capturing and 1 or SKIP_STEPS
  for _ = 1, steps do
    App.update(DT)
    if coroutine.status(co) ~= "dead" then
      local ok, err = coroutine.resume(co, DT)
      if not ok then fail("脚本出错：" .. tostring(err) .. "\n" .. debug.traceback(co)) ; D.done = true end
    end
    if D.done or D.capturing ~= (steps == 1) then break end
  end
end

-- 箭头光标（录屏不带系统光标，这里自己画）
local ARROW = { 0, 0, 0, 25, 6.5, 19, 11, 29, 15, 27, 10.5, 17.5, 18, 17.5 }
local function drawCursor(x, y)
  local s = love.graphics.getHeight() / 720 * 1.1
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.scale(s, s)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.polygon("fill", ARROW)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.setLineWidth(1.4)
  love.graphics.polygon("line", ARROW)
  love.graphics.pop()
end

function D.afterDraw()
  local W, H = love.graphics.getDimensions()
  love.graphics.setScissor()
  love.graphics.origin()
  if D.blackout then
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, W, H)
  elseif D.cursor then
    drawCursor(D.cursor[1], D.cursor[2])
  end
  if D.fade > 0 then
    love.graphics.setColor(0, 0, 0, D.fade)
    love.graphics.rectangle("fill", 0, 0, W, H)
  end
  love.graphics.setColor(1, 1, 1, 1)
  if D.capturing and not D.finished then
    love.graphics.captureScreenshot(function(img)
      pipe:write(img:getString())
      img:release()
    end)
    D.frame = D.frame + 1
  end
  if D.done and not D.finished then
    D.finished = true
    D.quitNext = true
  elseif D.quitNext then
    D.quitNext = false
    pipe:close()
    ev("quit", D.frame, D.failed and "FAIL" or "OK")
    love.event.quit(D.failed and 1 or 0)
  end
end

return D
