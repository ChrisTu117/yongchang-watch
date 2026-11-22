#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# 录制演示视频（约 3 分半，1920x1080，30 帧）：
#   1. 把游戏复制到临时目录，套上 tools/demo/ 的录制入口，在虚拟显示器里用 LÖVE 11.5 运行；
#      演示驱动 tools/demo/demo.lua 按固定步长推进游戏，每帧截图经管道交给 ffmpeg。
#   2. tools/mix_demo_audio.py 按事件表把游戏自带的音效、音乐混成音轨，并生成字幕。
#   3. ffmpeg 合成：画面 + 音轨 + 字幕，输出 H.264/AAC 的 mp4。
#   4. tools/check_demo_video.py 验收（时长、分辨率、声音、三夜都守住、只用了游戏自带的声音）。
# 需要：love（11.5）、xvfb-run、ffmpeg（带 libass）、python3 + numpy、Noto Sans/Serif CJK 字体。
# 输出：build/demo/YongchangWatch-demo.mp4 及中间文件；结果 build/reports/demo-result.txt
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=build/demo
mkdir -p "$OUT" build/reports
TMP="$(mktemp -d)"
FF=""
cleanup() { [ -n "$FF" ] && kill "$FF" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
GAME="$TMP/game"
mkdir -p "$GAME"
cp -r src assets "$GAME/"
cp main.lua "$GAME/game_main.lua"
cp conf.lua "$GAME/game_conf.lua"
cp tools/demo/main.lua tools/demo/conf.lua tools/demo/demo.lua "$GAME/"
mkfifo "$TMP/frames"
ffmpeg -hide_banner -loglevel error -y -f rawvideo -pix_fmt rgba -s 1920x1080 -r 30 -i "$TMP/frames" \
  -c:v libx264 -preset veryfast -crf 16 -pix_fmt yuv420p "$OUT/video-raw.mp4" &
FF=$!
echo "录制中（游戏离线逐帧渲染，约 10–20 分钟）…"
ALSOFT_DRIVERS=null XDG_DATA_HOME="$TMP" DEMO_FIFO="$TMP/frames" \
  timeout 3600 xvfb-run -a -s "-screen 0 1920x1080x24" love "$GAME" > "$OUT/love-stdout.txt" 2>&1
CODE=$?
# 游戏没打开管道就退出时，给 ffmpeg 一个文件结束，免得它一直等
timeout 5 bash -c ": > '$TMP/frames'" 2>/dev/null
wait "$FF"; FFCODE=$?; FF=""
grep '^DEMOEV' "$OUT/love-stdout.txt" | cut -f2- > "$OUT/events.tsv"
grep -v '^DEMOEV' "$OUT/love-stdout.txt" | tail -20 > "$OUT/love-stdout-tail.txt"
echo "love_exit=$CODE ffmpeg_exit=$FFCODE"
if [ "$CODE" != 0 ] || [ "$FFCODE" != 0 ]; then
  grep -E '^fail' "$OUT/events.tsv"; cat "$OUT/love-stdout-tail.txt"; exit 1
fi
FRAMES="$(ffprobe -v error -count_packets -select_streams v:0 -show_entries stream=nb_read_packets -of csv=p=0 "$OUT/video-raw.mp4")"
python3 tools/mix_demo_audio.py "$OUT/events.tsv" "$OUT" "$FRAMES" || exit 1
ffmpeg -hide_banner -loglevel error -y -i "$OUT/video-raw.mp4" -i "$OUT/audio.wav" \
  -vf "ass=$OUT/captions.ass" -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -r 30 \
  -c:a aac -b:a 192k -movflags +faststart -shortest "$OUT/YongchangWatch-demo.mp4" || exit 1
python3 tools/check_demo_video.py "$OUT" | tee build/reports/demo-result.txt
exit "${PIPESTATUS[0]}"
