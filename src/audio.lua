-- SPDX-License-Identifier: AGPL-3.0-only
-- 声音：音效可以叠放；音乐循环播放。声音设备不可用时静默降级，不影响游戏。
local love = require("love")

local A = { sfx = {}, pools = {}, musicName = nil, music = nil, muted = false, volume = 0.8 }

local SFX = { "bow", "gun", "hit", "repel", "gatehit", "breach", "gate", "saved", "build", "nomoney",
              "lantern", "drum", "gong", "tok", "click", "farm" }
local MUSIC = { "music_night", "music_festival", "music_title" }

function A.load()
  if not love.audio then return end
  for _, n in ipairs(SFX) do
    local ok, src = pcall(love.audio.newSource, "assets/sfx/" .. n .. ".wav", "static")
    if ok then A.sfx[n] = src; A.pools[n] = { src } end
  end
  A.tracks = {}
  for _, n in ipairs(MUSIC) do
    local ok, src = pcall(love.audio.newSource, "assets/sfx/" .. n .. ".ogg", "stream")
    if ok then src:setLooping(true); A.tracks[n] = src end
  end
end

function A.play(name, vol, pitch)
  if A.muted then return end
  local pool = A.pools[name]
  if not pool then return end
  local src
  for _, s in ipairs(pool) do
    if not s:isPlaying() then src = s; break end
  end
  if not src then
    if #pool >= 6 then return end
    src = pool[1]:clone()
    pool[#pool + 1] = src
  end
  src:setVolume((vol or 1) * A.volume)
  src:setPitch(pitch or 1)
  src:play()
end

function A.playMusic(name, vol)
  if A.musicName == name then return end
  if A.music then A.music:stop() end
  A.musicName, A.music = name, A.tracks and A.tracks[name]
  if A.music then
    A.music:setVolume((vol or 0.55) * A.volume * (A.muted and 0 or 1))
    A.music:play()
  end
end

function A.toggleMute()
  A.muted = not A.muted
  if A.music then A.music:setVolume(A.muted and 0 or 0.55 * A.volume) end
  return A.muted
end

return A
