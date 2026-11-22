# SPDX-License-Identifier: AGPL-3.0-only
"""演示视频的音轨和字幕（由 tools/record_demo.sh 调用）。

输入：录制时游戏打出的事件表 events.tsv（每行：类型、帧号、参数……，帧率见 start 行）。
- sfx / music：按帧号把 assets/sfx/ 里的音效和音乐放到时间轴上。规则和 src/audio.lua 一致：
  音量乘总音量 0.8；同一音效最多 6 个同时播放；音乐循环，换曲时停掉上一首。
  所以音轨里只有游戏自带的原创音效和音乐，没有别的声音。
- cap / card：生成 ASS 字幕（底部字幕带、片尾字卡）。
输出：<输出目录>/audio.wav（44.1 kHz 立体声 16 位）、<输出目录>/captions.ass
用法：python3 tools/mix_demo_audio.py <events.tsv> <输出目录>
"""
import os
import subprocess
import sys
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_DIR = os.path.join(ROOT, "assets", "sfx")
SR = 44100
MASTER = 0.8          # src/audio.lua 的 A.volume
MAX_SAME = 6          # src/audio.lua：同一音效最多 6 个音源


def decode(path):
    """用 ffmpeg 解码成 44.1 kHz 单声道 float。"""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "s16le", "-ac", "1", "-ar", str(SR), "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0


def ass_time(sec):
    cs = int(round(sec * 100))
    h, cs = divmod(cs, 360000)
    m, cs = divmod(cs, 6000)
    s, cs = divmod(cs, 100)
    return f"{h}:{m:02d}:{s:02d}.{cs:02d}"


def main():
    events_path, out_dir = sys.argv[1], sys.argv[2]
    rows = [line.rstrip("\n").split("\t") for line in open(events_path, encoding="utf-8") if line.strip()]
    fps = 30
    total = None
    for r in rows:
        if r[0] == "start":
            fps = int(r[3])
        if r[0] in ("end", "quit"):
            total = max(total or 0, int(r[1]))
    if total is None:
        sys.exit("事件表里没有 end 行，录制没有完成")
    if len(sys.argv) > 3:
        total = int(sys.argv[3])        # 以实际视频帧数为准
    length = int(total / fps * SR)
    mix = np.zeros(length + SR * 4, dtype=np.float32)

    cache = {}

    def clip(name, ext):
        if name not in cache:
            cache[name] = decode(os.path.join(SFX_DIR, f"{name}.{ext}"))
        return cache[name]

    # 音乐：从开始帧循环到下一首开始或结尾
    music = [(int(r[1]), r[2], float(r[3])) for r in rows if r[0] == "music"]
    for i, (frame, name, vol) in enumerate(music):
        start = int(frame / fps * SR)
        stop = int(music[i + 1][0] / fps * SR) if i + 1 < len(music) else length
        if stop <= start:
            continue
        track = clip(name, "ogg")
        reps = (stop - start) // len(track) + 1
        mix[start:stop] += np.tile(track, reps)[: stop - start] * vol * MASTER

    # 音效：同一音效同时最多 6 个
    active = {}
    used = set()
    for r in rows:
        if r[0] != "sfx":
            continue
        frame, name, vol, pitch = int(r[1]), r[2], float(r[3]), float(r[4])
        start = int(frame / fps * SR)
        src = clip(name, "wav")
        if abs(pitch - 1) > 1e-3:
            n = max(1, int(len(src) / pitch))
            src = np.interp(np.arange(n) * pitch, np.arange(len(src)), src).astype(np.float32)
        ends = [e for e in active.get(name, []) if e > start]
        if len(ends) >= MAX_SAME:
            active[name] = ends
            continue
        ends.append(start + len(src))
        active[name] = ends
        end = min(len(mix), start + len(src))
        mix[start:end] += src[: end - start] * vol * MASTER
        used.add(name)

    mix = mix[:length]
    # 开头 0.3 秒淡入、结尾 3 秒淡出
    fin = min(len(mix), int(0.3 * SR))
    mix[:fin] *= np.linspace(0, 1, fin, dtype=np.float32)
    fout = min(len(mix), 3 * SR)
    mix[len(mix) - fout:] *= np.linspace(1, 0, fout, dtype=np.float32)
    peak = float(np.max(np.abs(mix))) if len(mix) else 0.0
    if peak > 0.95:
        mix *= 0.95 / peak
    pcm = (np.clip(mix, -1, 1) * 32767).astype("<i2")
    stereo = np.repeat(pcm[:, None], 2, axis=1)
    os.makedirs(out_dir, exist_ok=True)
    with wave.open(os.path.join(out_dir, "audio.wav"), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(stereo.tobytes())

    # 字幕
    head = """[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Cap,Noto Sans CJK SC,46,&H00D8F0FF,&H00D8F0FF,&H00101010,&H80000000,0,0,0,0,100,100,2,0,1,2.5,0,2,60,60,30,1
Style: Card,Noto Serif CJK SC,40,&H00D8F0FF,&H00D8F0FF,&H00101010,&H80000000,0,0,0,0,100,100,2,0,1,0,0,5,60,60,0,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    lines = []
    caps = sorted((int(r[1]), int(r[2]), r[3]) for r in rows if r[0] == "cap")
    for i, (frame, dur, text) in enumerate(caps):
        end = frame + dur
        if i + 1 < len(caps):
            end = min(end, caps[i + 1][0])     # 下一条出现时上一条消失
        lines.append(f"Dialogue: 0,{ass_time(frame / fps)},{ass_time(end / fps)},Cap,,0,0,0,,{{\\fad(150,150)}}{text}")
    for r in rows:
        if r[0] == "card":
            frame, dur = int(r[1]), int(r[2])
            text = ("{\\fad(500,0)}{\\fs96\\b1}永昌守望{\\b0}\\N{\\fs44}队伍“什么都不会”（ChrisTu117）\\N\\N"
                    "{\\fs38}2026 开源游戏开发大赛参赛作品 · 主题「守·望」\\N"
                    "LÖVE 11.5 制作，同一份代码可在 Dora SSR 1.10 中运行\\N"
                    "代码 AGPL-3.0 · 原创音乐音效 CC BY 4.0 · 字体 Noto Serif CJK（SIL OFL 1.1）")
            lines.append(f"Dialogue: 0,{ass_time(frame / fps)},{ass_time((frame + dur) / fps)},Card,,0,0,0,,{text}")
    with open(os.path.join(out_dir, "captions.ass"), "w", encoding="utf-8") as f:
        f.write(head + "\n".join(lines) + "\n")
    print(f"音轨 {total / fps:.1f} 秒，峰值 {min(peak, 0.95):.2f}；用到的音效 {len(used)} 种，音乐 {len(music)} 段；字幕 {len(caps)} 条")


if __name__ == "__main__":
    main()
