#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# 生成大赛提交页要求的封面：16:9、1600×900、不超过 2 MB。
# 做法：把游戏复制到临时目录，只把 conf.lua 的窗口改成 1600×900，然后跑和 tools/run_autotest.sh 一样的
# 端到端自动测试（love --autotest），取其中第二夜的封面帧（src/autotest.lua 的 shot("cover")）。
# 画面是游戏实时画出来的，不是把 1280×720 的 cover.png 放大。
# 需要：love（11.5）、xvfb-run、ffprobe。输出：docs/screenshots/cover-1600x900.png
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
GAME="$TMP/game"
mkdir -p "$GAME"
cp -r main.lua conf.lua src assets "$GAME/"
sed -i -e 's/t.window.width = 1280/t.window.width = 1600/' -e 's/t.window.height = 720/t.window.height = 900/' "$GAME/conf.lua"
grep -q 't.window.width = 1600' "$GAME/conf.lua" && grep -q 't.window.height = 900' "$GAME/conf.lua" \
  || { echo "FAIL 没能把 conf.lua 的窗口改成 1600×900"; exit 1; }
set +e
XDG_DATA_HOME="$TMP" timeout 900 xvfb-run -a -s "-screen 0 1600x900x24" love "$GAME" --autotest > "$TMP/stdout.txt" 2>&1
CODE=$?
set -e
SHOT="$TMP/love/yongchang-watch/autotest/cover.png"
if [ "$CODE" -ne 0 ] || [ ! -f "$SHOT" ]; then
  grep -E '^\[FAIL\]|^AUTOTEST' "$TMP/stdout.txt" || tail -20 "$TMP/stdout.txt"
  echo "FAIL 自动测试没有通过或没有封面帧（exit=$CODE）"
  exit 1
fi
OUT=docs/screenshots/cover-1600x900.png
cp "$SHOT" "$OUT"
SIZE="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$OUT")"
BYTES="$(stat -c %s "$OUT")"
echo "$OUT $SIZE $BYTES 字节"
[ "$SIZE" = "1600x900" ] || { echo "FAIL 封面不是 1600×900"; exit 1; }
[ "$BYTES" -le 2097152 ] || { echo "FAIL 封面超过 2 MB"; exit 1; }
echo "COVER PASS"
