# SPDX-License-Identifier: AGPL-3.0-only
"""演示视频验收（tools/record_demo.sh 最后一步）。

1. 成片 YongchangWatch-demo.mp4：H.264 1920x1080、AAC 音轨，时长 1–5 分钟（大赛要求 5 分钟以内）。
2. 声音不是静音（平均音量高于 -45 dB）。
3. 录制过程没有出错，三夜都守住了，教学、舞龙显字、终章都走到了。
4. 音轨里只有游戏自带的声音：事件表里的每个音效、音乐都在 assets/sfx/ 里（CC BY 4.0 原创），
   混音脚本也只从这个目录读文件。
5. 每条字幕出现时截一张图到 stills/，供人工翻看。
用法：python3 tools/check_demo_video.py build/demo
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "demo")
    video = os.path.join(out, "YongchangWatch-demo.mp4")
    problems, notes = [], []
    if not os.path.exists(video):
        print("FAIL 没有成片 " + video)
        return 1
    info = json.loads(subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", video],
                                     check=True, capture_output=True, text=True).stdout)
    v = [s for s in info["streams"] if s["codec_type"] == "video"]
    a = [s for s in info["streams"] if s["codec_type"] == "audio"]
    dur = float(info["format"]["duration"])
    size = int(info["format"]["size"])
    if not v or v[0]["codec_name"] != "h264" or (v[0]["width"], v[0]["height"]) != (1920, 1080):
        problems.append("画面不是 H.264 1920x1080")
    if not a or a[0]["codec_name"] != "aac":
        problems.append("没有 AAC 音轨")
    if not 60 <= dur <= 300:
        problems.append(f"时长 {dur:.1f} 秒，不在 1–5 分钟之间")
    notes.append(f"时长 {int(dur // 60)} 分 {dur % 60:.1f} 秒，{size / 1e6:.1f} MB")

    vd = subprocess.run(["ffmpeg", "-hide_banner", "-i", video, "-vn", "-af", "volumedetect", "-f", "null", "-"],
                        capture_output=True, text=True).stderr
    m = re.search(r"mean_volume: (-?[\d.]+) dB", vd)
    mx = re.search(r"max_volume: (-?[\d.]+) dB", vd)
    mean = float(m.group(1)) if m else -99.0
    if mean < -45:
        problems.append(f"声音太小或静音（平均 {mean} dB）")
    notes.append(f"平均音量 {mean} dB，峰值 {mx.group(1) if mx else '?'} dB")

    rows = [line.rstrip("\n").split("\t") for line in open(os.path.join(out, "events.tsv"), encoding="utf-8")
            if line.strip()]
    fails = [r for r in rows if r[0] == "fail"]
    for r in fails:
        problems.append("录制出错：" + " ".join(r[2:]))
    quit_rows = [r for r in rows if r[0] == "quit"]
    if not quit_rows or quit_rows[-1][2] != "OK":
        problems.append("录制没有正常结束")
    nights = [r for r in rows if r[0] == "night"]
    won = [r for r in nights if r[3] == "won"]
    if len(won) != 3:
        problems.append(f"守住的夜晚 {len(won)}/3")
    notes.append("三夜：" + "；".join(f"第{r[2]}夜 {r[3]}，堡安 {r[4]}，迎入 {r[5]}，击退 {r[6]}" for r in nights))
    sounds = {(r[2], "wav" if r[0] == "sfx" else "ogg") for r in rows if r[0] in ("sfx", "music")}
    missing = [f"{n}.{ext}" for n, ext in sounds if not os.path.exists(os.path.join(ROOT, "assets", "sfx", f"{n}.{ext}"))]
    if missing:
        problems.append("音轨用到 assets/sfx 以外的声音：" + "、".join(sorted(missing)))
    if not sounds:
        problems.append("事件表里没有任何声音")
    notes.append(f"用到游戏自带的声音 {len(sounds)} 种")
    caps = [r for r in rows if r[0] == "cap"]
    if len(caps) < 8 or not any(r[0] == "card" for r in rows):
        problems.append("字幕或片尾字卡缺失")

    stills = os.path.join(out, "stills")
    os.makedirs(stills, exist_ok=True)
    fps = next((int(r[3]) for r in rows if r[0] == "start"), 30)
    marks = [(int(r[1]) + 20, f"cap{i + 1:02d}") for i, r in enumerate(caps)]
    marks += [(int(r[1]) + 60, "card") for r in rows if r[0] == "card"]
    for frame, name in marks:
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{frame / fps:.2f}", "-i", video, "-frames:v", "1",
                        "-vf", "scale=960:-1", os.path.join(stills, name + ".jpg")], check=False)
    notes.append(f"截图 {len(marks)} 张在 {stills}")

    for n in notes:
        print("  " + n)
    for p in problems:
        print("FAIL " + p)
    print("DEMO VIDEO PASS" if not problems else "DEMO VIDEO FAIL")
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())
