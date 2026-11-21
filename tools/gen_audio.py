# SPDX-License-Identifier: AGPL-3.0-only
"""生成游戏里全部音效和音乐。只用 Python 标准库合成波形；音乐再用 ffmpeg 压成 OGG。

生成的音频文件属于本项目原创资产，以 CC BY 4.0 授权（见 ASSETS.md）。
用法（仓库根目录）：python3 tools/gen_audio.py（设置 YCW_AUDIO_OUT 可输出到别的目录）
输出固定（随机数种子固定），重复运行得到同样的波形。
"""
import math
import os
import random
import struct
import subprocess
import sys
import wave

SR = 22050
OUT = os.environ.get("YCW_AUDIO_OUT") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")
rng = random.Random(20261121)


def write_wav(name, samples, sr=SR):
    path = os.path.join(OUT, name)
    peak = max(1e-9, max(abs(s) for s in samples))
    gain = 0.89 / peak if peak > 0.89 else 1.0
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * gain)) * 32767)) for s in samples))
    return path


def env(n, attack=0.005, decay=0.2, sr=SR):
    a = max(1, int(attack * sr))
    out = []
    for i in range(n):
        if i < a:
            out.append(i / a)
        else:
            out.append(math.exp(-(i - a) / (decay * sr)))
    return out


def noise(n):
    return [rng.uniform(-1, 1) for _ in range(n)]


def lowpass(x, alpha):
    y, prev = [], 0.0
    for s in x:
        prev = prev + alpha * (s - prev)
        y.append(prev)
    return y


def sine_sweep(n, f0, f1, sr=SR):
    out, ph = [], 0.0
    for i in range(n):
        f = f0 + (f1 - f0) * i / n
        ph += 2 * math.pi * f / sr
        out.append(math.sin(ph))
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(n)]


def mul(a, b):
    return [x * y for x, y in zip(a, b)]


def scale(a, k):
    return [x * k for x in a]


def pluck(freq, dur, damp=0.996, bright=0.5, sr=SR):
    """Karplus-Strong 拨弦（类似古筝的音色）。"""
    n = int(dur * sr)
    period = max(2, int(sr / freq))
    buf = [rng.uniform(-1, 1) for _ in range(period)]
    buf = lowpass(buf, bright)
    out = []
    for i in range(n):
        j = i % period
        nxt = buf[(i + 1) % period]
        v = buf[j]
        buf[j] = damp * 0.5 * (v + nxt)
        out.append(v)
    return out


def bell(freq, dur, partials=((1, 1.0), (2.76, 0.5), (5.4, 0.25), (8.93, 0.12)), decay=0.6, sr=SR):
    n = int(dur * sr)
    out = [0.0] * n
    for mult, amp in partials:
        f = freq * mult
        d = decay / mult ** 0.5
        for i in range(n):
            out[i] += amp * math.sin(2 * math.pi * f * i / sr) * math.exp(-i / (d * sr))
    return out


def gong(dur=2.4, sr=SR):
    n = int(dur * sr)
    parts = [(110, 1.0, 1.6), (163, 0.7, 1.2), (231, 0.5, 1.0), (297, 0.35, 0.8), (418, 0.25, 0.6)]
    out = [0.0] * n
    for f, a, d in parts:
        for i in range(n):
            t = i / sr
            wob = 1 + 0.004 * math.sin(2 * math.pi * 3 * t)
            out[i] += a * math.sin(2 * math.pi * f * wob * t) * math.exp(-t / d)
    hit = mul(noise(int(0.05 * sr)), env(int(0.05 * sr), 0.001, 0.015))
    return mix(out, scale(hit, 0.6))


def drum(sr=SR, f0=95, f1=48, dur=0.55):
    n = int(dur * sr)
    body = mul(sine_sweep(n, f0, f1), env(n, 0.002, 0.18))
    skin = mul(lowpass(noise(n), 0.15), env(n, 0.001, 0.03))
    return mix(body, scale(skin, 0.5))


def woodblock(sr=SR):
    n = int(0.12 * sr)
    return mul(mix(sine_sweep(n, 900, 820), scale(sine_sweep(n, 1500, 1400), 0.4)), env(n, 0.001, 0.025))


def make_sfx():
    n = int(0.18 * SR)
    write_wav("bow.wav", mix(scale(mul(sine_sweep(n, 520, 260), env(n, 0.002, 0.05)), 0.8),
                             scale(mul(lowpass(noise(n), 0.5), env(n, 0.001, 0.02)), 0.5)))
    n = int(0.45 * SR)
    write_wav("gun.wav", mix(mul(lowpass(noise(n), 0.35), env(n, 0.001, 0.09)),
                             scale(mul(sine_sweep(n, 120, 50), env(n, 0.001, 0.1)), 0.7)))
    n = int(0.09 * SR)
    write_wav("hit.wav", mul(mix(sine_sweep(n, 300, 150), scale(noise(n), 0.3)), env(n, 0.001, 0.03)))
    n = int(0.3 * SR)
    write_wav("repel.wav", mul(mix(sine_sweep(n, 420, 180), scale(sine_sweep(n, 630, 270), 0.4)), env(n, 0.002, 0.08)))
    n = int(0.25 * SR)
    write_wav("gatehit.wav", mix(mul(sine_sweep(n, 95, 60), env(n, 0.001, 0.07)),
                                 scale(mul(lowpass(noise(n), 0.2), env(n, 0.001, 0.04)), 0.7)))
    n = int(1.0 * SR)
    write_wav("breach.wav", mix(mul(lowpass(noise(n), 0.25), env(n, 0.002, 0.3)),
                                scale(mul(sine_sweep(n, 70, 35), env(n, 0.002, 0.4)), 0.8)))
    n = int(0.45 * SR)
    creak = [math.sin(2 * math.pi * (140 + 40 * math.sin(2 * math.pi * 7 * i / SR)) * i / SR) for i in range(n)]
    creak = [1 if c > 0.2 else (-1 if c < -0.2 else 0) for c in creak]
    write_wav("gate.wav", scale(mul(lowpass(creak, 0.2), env(n, 0.03, 0.15)), 0.6))
    write_wav("saved.wav", mix(bell(659.25, 0.9, decay=0.35), [0.0] * int(0.09 * SR) + bell(880.0, 0.8, decay=0.35)))
    k = woodblock()
    write_wav("build.wav", k + [0.0] * int(0.06 * SR) + scale(k, 0.8))
    n = int(0.22 * SR)
    buzz = [(1 if math.sin(2 * math.pi * 110 * i / SR) > 0 else -1) for i in range(n)]
    write_wav("nomoney.wav", scale(mul(lowpass(buzz, 0.1), env(n, 0.005, 0.08)), 0.5))
    n = int(0.9 * SR)
    whoosh = lowpass(noise(n), 0.05)
    write_wav("lantern.wav", mul(whoosh, [math.sin(math.pi * i / n) for i in range(n)]))
    write_wav("drum.wav", drum())
    write_wav("gong.wav", gong())
    write_wav("tok.wav", woodblock())
    n = int(0.05 * SR)
    write_wav("click.wav", mul(sine_sweep(n, 1200, 900), env(n, 0.001, 0.012)))
    write_wav("farm.wav", scale(bell(1046.5, 0.4, decay=0.15), 0.5))


PENTA = {"C": 261.63, "D": 293.66, "E": 329.63, "G": 392.00, "A": 440.00}


def note(name):
    base = PENTA[name[0]]
    octave = int(name[1:]) - 4
    return base * (2 ** octave)


def place(track, start, sig, gain=1.0):
    s = int(start * SR)
    need = s + len(sig)
    if len(track) < need:
        track.extend([0.0] * (need - len(track)))
    for i, v in enumerate(sig):
        track[s + i] += v * gain


def make_music_night():
    """夜曲：古筝式拨弦，五声音阶，慢速；低音持续。约 32 秒循环。"""
    bpm = 66
    beat = 60 / bpm
    melody = ["E4", "G4", "A4", "-", "G4", "E4", "D4", "-", "E4", "G4", "C5", "A4", "G4", "-", "-", "-",
              "A4", "C5", "D5", "-", "C5", "A4", "G4", "-", "E4", "D4", "E4", "G4", "E4", "-", "-", "-",
              "D4", "E4", "G4", "-", "A4", "G4", "E4", "D4", "C4", "D4", "E4", "-", "D4", "-", "-", "-",
              "E4", "G4", "A4", "C5", "A4", "G4", "E4", "-", "D4", "E4", "D4", "C4", "C4", "-", "-", "-"]
    total = len(melody) * beat / 2
    track = [0.0] * int(total * SR)
    for i, n in enumerate(melody):
        if n != "-":
            place(track, i * beat / 2, pluck(note(n), 2.2, damp=0.997, bright=0.45), 0.55)
    bass = ["C3", "A3", "D3", "G3", "C3", "A3", "G3", "C3"]
    for i, b in enumerate(bass):
        place(track, i * beat * 4, pluck(note(b) / 2, 3.5, damp=0.998, bright=0.25), 0.5)
    # 远处海浪
    n = len(track)
    waves = lowpass(noise(n), 0.02)
    for i in range(n):
        track[i] += waves[i] * 0.6 * (0.6 + 0.4 * math.sin(2 * math.pi * i / (SR * 8)))
    return track[: int(total * SR)]


def make_music_festival():
    """节庆：锣鼓点 + 拨弦旋律，较快。约 16 秒循环。"""
    bpm = 120
    beat = 60 / bpm
    bars = 8
    total = bars * 4 * beat
    track = [0.0] * int(total * SR)
    d = drum()
    g = gong(1.6)
    k = woodblock()
    pattern = "D.dDD.d.D.dDDdD."  # 两小节一循环：D 重鼓 d 轻鼓
    for rep in range(bars // 2):
        for i, c in enumerate(pattern):
            t = rep * 8 * beat + i * beat / 2
            if c == "D":
                place(track, t, d, 0.8)
            elif c == "d":
                place(track, t, d, 0.4)
        place(track, rep * 8 * beat, g, 0.35)
        for i in range(8):
            place(track, rep * 8 * beat + i * beat + beat / 2, k, 0.25)
    melody = ["G4", "A4", "C5", "A4", "G4", "E4", "G4", "-", "A4", "C5", "D5", "C5", "A4", "G4", "A4", "-",
              "E5", "D5", "C5", "A4", "G4", "A4", "C5", "-", "D5", "C5", "A4", "G4", "E4", "D4", "C4", "-"]
    for i, n in enumerate(melody):
        if n != "-":
            place(track, i * beat, pluck(note(n), 1.2, damp=0.994, bright=0.6), 0.45)
    return track[: int(total * SR)]


def make_music_title():
    """标题：慢速琶音。约 20 秒循环。"""
    beat = 60 / 54
    seq = ["C4", "G4", "C5", "E5", "D5", "A4", "D4", "A4", "E4", "G4", "C5", "G4", "A3", "E4", "A4", "C5",
           "G3", "D4", "G4", "A4"]
    total = len(seq) * beat
    track = [0.0] * int(total * SR)
    for i, n in enumerate(seq):
        place(track, i * beat, pluck(note(n), 3.0, damp=0.998, bright=0.4), 0.6)
    return track[: int(total * SR)]


def to_ogg(wav_path, ogg_name):
    ogg = os.path.join(OUT, ogg_name)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "3",
                    "-ar", str(SR), "-ac", "1", "-map_metadata", "-1", "-fflags", "+bitexact",
                    "-flags:a", "+bitexact", ogg], check=True)
    os.remove(wav_path)


def main():
    os.makedirs(OUT, exist_ok=True)
    make_sfx()
    for name, fn in (("music_night", make_music_night), ("music_festival", make_music_festival),
                     ("music_title", make_music_title)):
        p = write_wav(name + ".tmp.wav", fn())
        to_ogg(p, name + ".ogg")
    for f in sorted(os.listdir(OUT)):
        print(f, os.path.getsize(os.path.join(OUT, f)))


if __name__ == "__main__":
    sys.exit(main())
